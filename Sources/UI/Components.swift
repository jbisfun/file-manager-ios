import FossifyCommons
import QuickLook
import QuickLookThumbnailing
import SwiftUI
import UIKit

/// MyFloatingActionButton.
struct Fab: View {
    @Environment(\.palette) private var palette
    var icon = "plus"
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 22, weight: .medium))
                .foregroundStyle(palette.onPrimary)
                .frame(width: 56, height: 56)
                .background(Circle().fill(palette.primaryColor))
                .shadow(color: .black.opacity(0.3), radius: 4, y: 2)
        }
        .buttonStyle(.plain)
    }
}

/// The italic "No items found." placeholders, with an optional underlined action.
struct Placeholder: View {
    @Environment(\.palette) private var palette
    let text: String
    var secondary: String?
    var action: String?
    var onAction: () -> Void = {}

    var body: some View {
        VStack(spacing: 16) {
            Text(text)
                .font(.system(size: 17).italic())
                .foregroundStyle(palette.textColor)
                .multilineTextAlignment(.center)
            if let secondary {
                Text(secondary)
                    .font(.system(size: 15).italic())
                    .foregroundStyle(palette.secondaryText)
                    .multilineTextAlignment(.center)
            }
            if let action {
                Button(action: onAction) {
                    Text(action).font(.system(size: 17)).underline().foregroundStyle(palette.primaryColor)
                }
            }
        }
        .padding(32)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .padding(.top, 40)
    }
}

/// openPathIntent(): the system viewer for images, video, audio, PDFs, documents...
struct QuickLookPreview: UIViewControllerRepresentable {
    let url: URL
    @Environment(\.dismiss) private var dismiss

    func makeUIViewController(context: Context) -> UINavigationController {
        let ql = QLPreviewController()
        ql.dataSource = context.coordinator
        ql.navigationItem.leftBarButtonItem = UIBarButtonItem(systemItem: .close, primaryAction: UIAction { _ in context.coordinator.close() })
        return UINavigationController(rootViewController: ql)
    }

    func updateUIViewController(_ vc: UINavigationController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(url: url, close: { dismiss() }) }

    final class Coordinator: NSObject, QLPreviewControllerDataSource {
        let url: URL
        let close: () -> Void
        init(url: URL, close: @escaping () -> Void) {
            self.url = url
            self.close = close
        }
        func numberOfPreviewItems(in controller: QLPreviewController) -> Int { 1 }
        func previewController(_ controller: QLPreviewController, previewItemAt index: Int) -> QLPreviewItem { url as NSURL }
    }
}

/// System folder picker, for adding storages.
struct FolderPicker: UIViewControllerRepresentable {
    let onPick: (URL) -> Void

    func makeUIViewController(context: Context) -> UIDocumentPickerViewController {
        let vc = UIDocumentPickerViewController(forOpeningContentTypes: [.folder])
        vc.delegate = context.coordinator
        return vc
    }

    func updateUIViewController(_ vc: UIDocumentPickerViewController, context: Context) {}
    func makeCoordinator() -> Coordinator { Coordinator(onPick: onPick) }

    final class Coordinator: NSObject, UIDocumentPickerDelegate {
        let onPick: (URL) -> Void
        init(onPick: @escaping (URL) -> Void) { self.onPick = onPick }
        func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
            if let url = urls.first { onPick(url) }
        }
    }
}

/// Glide stand-in: QuickLook thumbnails, cached.
@MainActor
final class Thumbnails {
    static let shared = Thumbnails()
    private let cache = NSCache<NSString, UIImage>()

    func cached(_ key: String) -> UIImage? { cache.object(forKey: key as NSString) }

    func load(_ path: String, modified: Date, size: CGFloat) async -> UIImage? {
        let key = "\(path)|\(modified.timeIntervalSince1970)|\(Int(size))"
        if let image = cache.object(forKey: key as NSString) { return image }
        let request = QLThumbnailGenerator.Request(fileAt: URL(fileURLWithPath: path), size: CGSize(width: size, height: size),
                                                   scale: UIScreen.main.scale, representationTypes: .thumbnail)
        guard let rep = try? await QLThumbnailGenerator.shared.generateBestRepresentation(for: request) else { return nil }
        cache.setObject(rep.uiImage, forKey: key as NSString)
        return rep.uiImage
    }
}

/// getFilePlaceholderDrawables(): an icon per file type.
func fileTypeIcon(_ path: String) -> String {
    let ext = path.fileExtension.lowercased()
    switch ext {
    case "pdf": return "doc.richtext"
    case "zip", "rar", "7z", "tar", "gz", "jar": return "doc.zipper"
    case "apk", "ipa": return "app.badge"
    case "txt", "md", "log": return "doc.plaintext"
    case "html", "htm", "xml", "json", "js", "css", "kt", "java", "swift", "py", "c", "h", "cpp", "sh": return "chevron.left.forwardslash.chevron.right"
    case "csv", "xls", "xlsx", "ods", "numbers": return "tablecells"
    case "ppt", "pptx", "odp", "key": return "rectangle.on.rectangle"
    case "doc", "docx", "odt", "rtf", "pages": return "doc.text"
    case "vcf": return "person.crop.rectangle"
    case "ics": return "calendar"
    case "ttf", "otf": return "textformat"
    default:
        switch FileCategory.of(path) {
        case .images: return "photo"
        case .videos: return "film"
        case .audio: return "music.note"
        default: return "doc"
        }
    }
}

/// The item icon: tinted folder, thumbnail, or file type placeholder.
struct ItemIcon: View {
    @Environment(\.palette) private var palette
    let item: FileDirItem
    let size: CGFloat
    @State private var image: UIImage?

    var body: some View {
        Group {
            if item.isDirectory {
                Image(systemName: "folder.fill")
                    .resizable()
                    .scaledToFit()
                    .padding(size * 0.1)
                    .foregroundStyle(palette.primaryColor.opacity(0.7))
            } else if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
                    .frame(width: size, height: size)
                    .clipShape(RoundedRectangle(cornerRadius: 4))
            } else {
                Image(systemName: fileTypeIcon(item.path))
                    .resizable()
                    .scaledToFit()
                    .padding(size * 0.18)
                    .foregroundStyle(palette.secondaryText)
            }
        }
        .frame(width: size, height: size)
        .task(id: "\(item.path)|\(item.modified)") {
            guard !item.isDirectory else { return }
            image = await Thumbnails.shared.load(item.path, modified: item.modified, size: size)
        }
    }
}

/// Text with the search query highlighted in the primary color (highlightTextPart).
func highlighted(_ text: String, _ query: String, color: Color) -> AttributedString {
    var s = AttributedString(text)
    guard query.count > 1 else { return s }
    let normalized = text.normalizedForSearch.lowercased(), needle = query.normalizedForSearch.lowercased()
    var start = normalized.startIndex
    while let r = normalized.range(of: needle, range: start..<normalized.endIndex) {
        let lower = normalized.distance(from: normalized.startIndex, to: r.lowerBound)
        let length = normalized.distance(from: r.lowerBound, to: r.upperBound)
        let chars = s.characters
        if lower + length <= chars.count {
            let a = chars.index(chars.startIndex, offsetBy: lower), b = chars.index(a, offsetBy: length)
            s[a..<b].foregroundColor = color
        }
        start = r.upperBound
    }
    return s
}

extension Int {
    /// R.plurals.items.
    var itemsText: String { "\(self) item\(self == 1 ? "" : "s")" }
}
