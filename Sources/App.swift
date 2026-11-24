import FossifyCommons
import Observation
import SwiftUI
import UIKit

enum Route: Hashable {
    case settings
    case customizeColors
    case about
    case favorites
    case mimeTypes(FileCategory)
    case readText(String)
    case decompress(String)
}

@MainActor
@Observable
final class Router {
    var path: [Route] = []
    var toast: String?
    /// QuickLook preview of a file (openPathIntent).
    var preview: URL?
    /// A folder the main screen should switch to (launcher shortcut / incoming folder URL).
    var openFolder: String?
    /// A shared file waiting for a destination folder (SaveAsActivity).
    var saveAs: URL?
    /// Pending password prompt (SecurityDialog).
    var securityCheck: SecurityCheck?

    /// handleHiddenFolderPasswordProtection().
    func hiddenProtected(_ action: @escaping () -> Void) {
        if let check = StoredProtection.check(.hiddenItems, onSuccess: action) { securityCheck = check } else { action() }
    }

    /// handleDeletePasswordProtection().
    func deleteProtected(_ action: @escaping () -> Void) {
        if let check = SecurityCheck.deleteProtection(action) { securityCheck = check } else { action() }
    }

    func push(_ r: Route) { path.append(r) }
    func pop() { if !path.isEmpty { path.removeLast() } }

    /// tryOpenPathIntent(): archives and text files open in the app, the rest in QuickLook.
    func open(_ path: String, as type: OpenAs = .default) {
        switch type {
        case .default:
            if path.isZipFile {
                push(.decompress(path))
            } else if path.isTextFile {
                push(.readText(path))
            } else {
                preview = URL(fileURLWithPath: path)
            }
        case .text:
            push(.readText(path))
        case .image, .audio, .video:
            preview = OpenAs.alias(path, type)
        case .other:
            if !Launcher.openWith(URL(fileURLWithPath: path)) { toast = "No valid app found" }
        }
    }

    /// Files handed to the app ("Open in", share sheet, launcher).
    func handleIncoming(_ url: URL) {
        guard url.isFileURL else { return }
        _ = url.startAccessingSecurityScopedResource()
        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir) else { return }
        path = []
        if isDir.boolValue {
            if StorageRoot.containing(url.path, in: Storage.shared.roots) == nil { Storage.shared.addFolder(url) }
            openFolder = url.path
        } else if url.path.isZipFile {
            push(.decompress(url.path))
        } else if url.path.isTextFile {
            push(.readText(url.path))
        } else {
            saveAs = url
        }
    }
}

/// OPEN_AS_* of the "Open as" dialog.
enum OpenAs: Int {
    case `default` = 0, text, image, audio, video, other

    /// QuickLook picks the viewer from the file extension, so "open as" previews a link
    /// to the file named with a matching extension.
    static func alias(_ path: String, _ type: OpenAs) -> URL {
        let ext: String
        switch type {
        case .image: ext = "jpg"
        case .audio: ext = "mp3"
        default: ext = "mp4"
        }
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("OpenAs", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let link = dir.appendingPathComponent(path.filenameFromPath + "." + ext)
        try? FileManager.default.removeItem(at: link)
        if (try? FileManager.default.linkItem(atPath: path, toPath: link.path)) == nil {
            try? FileManager.default.copyItem(atPath: path, toPath: link.path)
        }
        return link
    }
}

/// The whole app as one view: the standalone app's window content, and what the launcher
/// presents. `openURL` is a file or folder handed over by the launcher.
public struct FileManagerRoot: View {
    @State private var router = Router()
    private let openURL: URL?

    public init(openURL: URL? = nil) {
        self.openURL = openURL
    }

    public var body: some View {
        RootView()
            .environment(router)
            .environment(Config.shared)
            .environment(Storage.shared)
            .appLock()
            .fossifyTheme()
            .onOpenURL { router.handleIncoming($0) }
            .onAppear { if let openURL { router.handleIncoming(openURL) } }
    }
}

struct RootView: View {
    @Environment(Router.self) private var router
    @Environment(Config.self) private var config

    var body: some View {
        @Bindable var router = router
        GeometryReader { geo in
            NavigationStack(path: $router.path) {
                MainView()
                    .navigationDestination(for: Route.self) { route in
                        Group {
                            switch route {
                            case .settings: SettingsView()
                            case .customizeColors: CustomizeColorsView()
                            case .about: AboutView(app: .fileManager)
                            case .favorites: FavoritesView()
                            case .mimeTypes(let category): MimeTypesView(category: category)
                            case .readText(let path): ReadTextView(path: path)
                            case .decompress(let path): DecompressView(path: path)
                            }
                        }
                        .toolbar(.hidden, for: .navigationBar)
                        .paletteBackground()
                    }
                    .toolbar(.hidden, for: .navigationBar)
            }
            .onAppear { config.isLandscape = geo.size.width > geo.size.height }
            .onChange(of: geo.size) { _, s in config.isLandscape = s.width > s.height }
        }
        .toast($router.toast)
        .securityCheck($router.securityCheck)
        .fullScreenCover(item: Binding(get: { router.preview.map(IdentifiedURL.init) }, set: { router.preview = $0?.url })) { item in
            QuickLookPreview(url: item.url).ignoresSafeArea()
        }
        .sheet(item: Binding(get: { router.saveAs.map(IdentifiedURL.init) }, set: { router.saveAs = $0?.url })) { item in
            SaveIncomingDialog(url: item.url)
        }
    }
}

struct IdentifiedURL: Identifiable {
    let url: URL
    var id: URL { url }
}

/// Files for `.sheet(item:)` with a stable identity.
struct URLList: Identifiable {
    let urls: [URL]
    var id: String { urls.map(\.path).joined(separator: "|") }
}
