import FossifyCommons
import SwiftUI
import UIKit

/// ReadTextActivity: the built-in text editor.
struct ReadTextView: View {
    @Environment(Router.self) private var router
    @Environment(Config.self) private var config
    @Environment(\.palette) private var palette
    let path: String

    @State private var filePath = ""
    @State private var text = ""
    @State private var original = ""
    @State private var loaded = false
    @State private var searchActive = false
    @State private var searchQuery = ""
    @State private var searchIndex = 0
    @State private var saveAs = false
    @State private var exitAfterSave = false
    @State private var askSave = false
    @State private var lastSavePrompt = Date.distantPast
    @FocusState private var searchFocused: Bool

    private var matches: [NSRange] {
        guard searchQuery.count > 1 else { return [] }
        let ns = text as NSString
        var result: [NSRange] = []
        var range = NSRange(location: 0, length: ns.length)
        while true {
            let r = ns.range(of: searchQuery, options: [.caseInsensitive, .diacriticInsensitive], range: range)
            if r.location == NSNotFound { break }
            result.append(r)
            range = NSRange(location: r.location + max(r.length, 1), length: ns.length - r.location - max(r.length, 1))
        }
        return result
    }

    var body: some View {
        let matches = matches
        VStack(spacing: 0) {
            TopBar(title: path.filenameFromPath, onBack: back, background: nil, tint: nil) {
                IconButton(icon: "magnifyingglass") {
                    searchActive = true
                    searchFocused = true
                }
                IconButton(icon: "square.and.arrow.down") { save() }
                Menu {
                    Button { saveAs = true } label: { Label("Save as", systemImage: "square.and.arrow.down.on.square") }
                    Button { print() } label: { Label("Print", systemImage: "printer") }
                    Button { Launcher.openWith(URL(fileURLWithPath: path)) } label: { Label("Open with", systemImage: "arrow.up.forward.app") }
                } label: {
                    Image(systemName: "ellipsis").rotationEffect(.degrees(90)).font(.system(size: 18)).frame(width: 44, height: 48)
                }
            }
            if searchActive {
                HStack(spacing: 0) {
                    TextField("", text: $searchQuery, prompt: Text("Search").foregroundStyle(palette.onPrimary.opacity(0.7)))
                        .focused($searchFocused)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                        .submitLabel(.search)
                        .onSubmit { next(matches.count) }
                        .padding(.leading, 16)
                    IconButton(icon: "chevron.up") { previous(matches.count) }
                    IconButton(icon: "chevron.down") { next(matches.count) }
                    IconButton(icon: "xmark") { closeSearch() }
                }
                .foregroundStyle(palette.onPrimary)
                .background(palette.primaryColor)
            }
            EditorTextView(text: $text, zoom: Binding(get: { config.editorTextZoom }, set: { config.editorTextZoom = $0 }),
                           baseSize: palette.fontSize, textColor: UIColor(palette.textColor), highlight: UIColor(palette.primaryColor),
                           matches: matches, current: matches.isEmpty ? nil : matches[min(searchIndex, matches.count - 1)],
                           focusOnLoad: loaded && original.isEmpty)
        }
        .background(palette.backgroundColor.ignoresSafeArea())
        .task { load() }
        .onChange(of: searchQuery) { _, _ in searchIndex = 0 }
        .sheet(isPresented: $saveAs) {
            SaveAsDialog(path: filePath) { newPath in write(to: newPath) }
        }
        .alert("You have unsaved changes. Save before exit?", isPresented: $askSave) {
            Button("Discard", role: .destructive) { router.pop() }
            Button("Save") {
                exitAfterSave = true
                save()
            }
        }
    }

    private func load() {
        guard !loaded else { return }
        filePath = path
        let url = URL(fileURLWithPath: path)
        let data = (try? Data(contentsOf: url)) ?? Data()
        let content = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .isoLatin1) ?? ""
        text = content
        original = content
        loaded = true
    }

    /// onBackPressedCompat().
    private func back() {
        if searchActive {
            closeSearch()
        } else if text != original && Date().timeIntervalSince(lastSavePrompt) > 3 {
            lastSavePrompt = Date()
            askSave = true
        } else {
            router.pop()
        }
    }

    private func closeSearch() {
        searchQuery = ""
        searchActive = false
        searchFocused = false
    }

    private func next(_ count: Int) {
        guard count > 0 else { return }
        searchIndex = searchIndex < count - 1 ? searchIndex + 1 : 0
    }

    private func previous(_ count: Int) {
        guard count > 0 else { return }
        searchIndex = searchIndex > 0 ? searchIndex - 1 : count - 1
    }

    private func save() {
        if filePath.isEmpty { saveAs = true } else { write(to: filePath) }
    }

    /// saveTextContent().
    private func write(to target: String) {
        do {
            try text.write(toFile: target, atomically: true, encoding: .utf8)
            router.toast = "File saved successfully"
            if target == filePath { original = text }
            UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
            if exitAfterSave { router.pop() }
        } catch {
            router.toast = "An unknown error occurred"
        }
        exitAfterSave = false
    }

    /// printText().
    private func print() {
        let controller = UIPrintInteractionController.shared
        let info = UIPrintInfo(dictionary: nil)
        info.jobName = filePath.isEmpty ? "File Manager" : filePath.filenameFromPath
        info.outputType = .general
        controller.printInfo = info
        controller.printFormatter = UISimpleTextPrintFormatter(text: text)
        controller.present(animated: true)
    }
}

/// GestureEditText: an editable text view with pinch-to-zoom and search highlighting.
struct EditorTextView: UIViewRepresentable {
    @Binding var text: String
    @Binding var zoom: Double
    let baseSize: CGFloat
    let textColor: UIColor
    let highlight: UIColor
    let matches: [NSRange]
    let current: NSRange?
    let focusOnLoad: Bool

    func makeUIView(context: Context) -> UITextView {
        let v = UITextView()
        v.delegate = context.coordinator
        v.backgroundColor = .clear
        v.autocorrectionType = .no
        v.autocapitalizationType = .none
        v.smartQuotesType = .no
        v.smartDashesType = .no
        v.alwaysBounceVertical = true
        v.keyboardDismissMode = .interactive
        v.textContainerInset = UIEdgeInsets(top: 12, left: 12, bottom: 24, right: 12)
        v.addGestureRecognizer(UIPinchGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.pinch(_:))))
        return v
    }

    func updateUIView(_ v: UITextView, context: Context) {
        context.coordinator.parent = self
        let font = UIFont.systemFont(ofSize: baseSize * CGFloat(zoom) / 1.2)
        if v.text != text { v.text = text }
        v.font = font
        v.textColor = textColor
        v.tintColor = highlight
        let storage = v.textStorage
        let full = NSRange(location: 0, length: storage.length)
        storage.beginEditing()
        storage.removeAttribute(.backgroundColor, range: full)
        for r in matches where NSMaxRange(r) <= storage.length {
            storage.addAttribute(.backgroundColor, value: highlight.withAlphaComponent(r == current ? 0.6 : 0.3), range: r)
        }
        storage.endEditing()
        if let current, current != context.coordinator.lastCurrent, NSMaxRange(current) <= storage.length {
            context.coordinator.lastCurrent = current
            v.scrollRangeToVisible(current)
        }
        if focusOnLoad && !context.coordinator.didFocus {
            context.coordinator.didFocus = true
            DispatchQueue.main.async { v.becomeFirstResponder() }
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator(parent: self) }

    final class Coordinator: NSObject, UITextViewDelegate {
        var parent: EditorTextView
        var lastCurrent: NSRange?
        var didFocus = false
        private var startZoom = 1.0

        init(parent: EditorTextView) { self.parent = parent }

        func textViewDidChange(_ textView: UITextView) { parent.text = textView.text }

        @objc func pinch(_ g: UIPinchGestureRecognizer) {
            switch g.state {
            case .began: startZoom = parent.zoom
            case .changed: parent.zoom = min(4, max(0.5, startZoom * Double(g.scale)))
            default: break
            }
        }
    }
}
