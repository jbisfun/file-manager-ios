import FossifyCommons
import SwiftUI

/// CreateNewItemDialog: a new folder or empty file in `path`.
struct CreateNewItemDialog: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.palette) private var palette
    let path: String
    let onDone: (Bool) -> Void
    @State private var name = ""
    @State private var folder = true
    @State private var error: String?
    @FocusState private var focused: Bool

    var body: some View {
        DialogFrame(title: "Create new", scroll: false) {
            DialogTextField(placeholder: "Name", text: $name).focused($focused)
            HStack(spacing: 24) {
                Button { folder = true } label: { RadioRow(title: "Folder", on: folder) }.buttonStyle(.plain).fixedSize()
                Button { folder = false } label: { RadioRow(title: "File", on: !folder) }.buttonStyle(.plain).fixedSize()
                Spacer()
            }
            if let error { Text(error).font(.system(size: 14)).foregroundStyle(.red) }
            DialogButtons {
                if name.isEmpty {
                    error = "Please enter a name"
                } else if !name.isAValidFilename {
                    error = "The name contains invalid characters"
                } else if FileManager.default.fileExists(atPath: "\(path)/\(name)") {
                    error = "A file or folder with that name already exists"
                } else {
                    let ok = FileOps.create("\(path)/\(name)", folder: folder)
                    dismiss()
                    onDone(ok)
                }
            }
        }
        .onAppear { focused = true }
    }
}

/// ChangeSortingDialog.
struct ChangeSortingDialog: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(Config.self) private var config
    @Environment(\.palette) private var palette
    let path: String
    @State private var sortBy = Sorting.byName
    @State private var descending = false
    @State private var numeric = false
    @State private var forFolder = false
    @State private var loaded = false

    var body: some View {
        DialogFrame(title: "Sort by") {
            radio(Sorting.byName, "Name")
            radio(Sorting.bySize, "Size")
            radio(Sorting.byDateModified, "Last modified")
            radio(Sorting.byExtension, "Extension")
            Divider().overlay(palette.divider).padding(.vertical, 8)
            Button { descending = false } label: { RadioRow(title: "Ascending", on: !descending) }.buttonStyle(.plain)
            Button { descending = true } label: { RadioRow(title: "Descending", on: descending) }.buttonStyle(.plain)
            Divider().overlay(palette.divider).padding(.vertical, 8)
            if sortBy == Sorting.byName {
                CheckRow(title: "Sort numeric parts by actual value", on: $numeric)
            }
            if !path.isEmpty {
                CheckRow(title: "Use for this folder only", on: $forFolder)
            }
            DialogButtons {
                var sorting = sortBy
                if descending { sorting |= Sorting.descending }
                if numeric && sortBy == Sorting.byName { sorting |= Sorting.useNumericValue }
                if forFolder {
                    config.saveCustomSorting(path, sorting)
                } else {
                    config.removeCustomSorting(path)
                    config.sorting = sorting
                }
                dismiss()
            }
        }
        .onAppear {
            guard !loaded else { return }
            loaded = true
            let current = config.getFolderSorting(path)
            sortBy = current & Sorting.bySize != 0 ? Sorting.bySize
                : current & Sorting.byDateModified != 0 ? Sorting.byDateModified
                : current & Sorting.byExtension != 0 ? Sorting.byExtension : Sorting.byName
            descending = current & Sorting.descending != 0
            numeric = current & Sorting.useNumericValue != 0
            forFolder = config.hasCustomSorting(path)
        }
    }

    private func radio(_ value: Int, _ title: String) -> some View {
        Button { sortBy = value } label: { RadioRow(title: title, on: sortBy == value) }.buttonStyle(.plain)
    }
}

/// ChangeViewTypeDialog.
struct ChangeViewTypeDialog: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(Config.self) private var config
    @Environment(\.palette) private var palette
    let path: String
    let showFolderCheck: Bool
    @State private var grid = false
    @State private var forFolder = false
    @State private var loaded = false

    var body: some View {
        DialogFrame(title: nil) {
            Button { grid = true } label: { RadioRow(title: "Grid", on: grid) }.buttonStyle(.plain)
            Button { grid = false } label: { RadioRow(title: "List", on: !grid) }.buttonStyle(.plain)
            if showFolderCheck {
                Divider().overlay(palette.divider).padding(.vertical, 8)
                CheckRow(title: "Use for this folder only", on: $forFolder)
            }
            DialogButtons {
                let type = grid ? ViewTypes.grid : ViewTypes.list
                if forFolder {
                    config.saveFolderViewType(path, type)
                } else {
                    config.removeFolderViewType(path)
                    config.viewType = type
                }
                dismiss()
            }
        }
        .onAppear {
            guard !loaded else { return }
            loaded = true
            grid = config.getFolderViewType(path) == ViewTypes.grid
            forFolder = config.hasCustomViewType(path)
        }
    }
}

/// CompressAsDialog: zip file name and destination folder.
struct CompressAsDialog: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(Config.self) private var config
    @Environment(Storage.self) private var storage
    @Environment(\.palette) private var palette
    let path: String
    let onConfirm: (String) -> Void
    @State private var name: String
    @State private var folder: String
    @State private var pickFolder = false
    @State private var error: String?

    init(path: String, onConfirm: @escaping (String) -> Void) {
        self.path = path
        self.onConfirm = onConfirm
        var isDir: ObjCBool = false
        FileManager.default.fileExists(atPath: path, isDirectory: &isDir)
        let filename = path.filenameFromPath
        let ext = isDir.boolValue ? "" : filename.fileExtension
        _name = State(initialValue: ext.isEmpty ? filename : String(filename.dropLast(ext.count + 1)))
        _folder = State(initialValue: path.parentPath)
    }

    var body: some View {
        DialogFrame(title: "Compress as", scroll: false) {
            DialogTextField(placeholder: "Name", text: $name)
            Button { pickFolder = true } label: {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Folder").font(.system(size: 13)).foregroundStyle(palette.secondaryText)
                    Text(storage.humanize(folder)).foregroundStyle(palette.textColor).lineLimit(2)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, 8)
            }
            .buttonStyle(.plain)
            if let error { Text(error).font(.system(size: 14)).foregroundStyle(.red) }
            DialogButtons {
                if name.isEmpty {
                    error = "Please enter a name"
                } else if !name.isAValidFilename {
                    error = "The name contains invalid characters"
                } else if FileManager.default.fileExists(atPath: "\(folder)/\(name).zip") {
                    error = "A file or folder with that name already exists"
                } else {
                    dismiss()
                    onConfirm("\(folder)/\(name).zip")
                }
            }
        }
        .sheet(isPresented: $pickFolder) {
            FilePickerDialog(path: folder, roots: storage.roots, showHidden: config.shouldShowHidden(), showFAB: true,
                             canAddShowHiddenButton: true, favorites: config.favorites) { folder = $0 }
        }
    }
}

/// ManageVisibleTabsDialog.
struct ManageVisibleTabsDialog: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(Config.self) private var config
    @State private var files = true
    @State private var recents = true
    @State private var storage = true
    @State private var loaded = false

    var body: some View {
        DialogFrame(title: nil) {
            CheckRow(title: "Files", on: $files)
            CheckRow(title: "Recent files", on: $recents)
            CheckRow(title: "Storage analysis", on: $storage)
            DialogButtons {
                var result = 0
                if files { result += MainTab.files.rawValue }
                if recents { result += MainTab.recents.rawValue }
                if storage { result += MainTab.storage.rawValue }
                config.showTabs = result == 0 ? MainTab.allMask : result
                dismiss()
            }
        }
        .onAppear {
            guard !loaded else { return }
            loaded = true
            files = config.isTabVisible(.files)
            recents = config.isTabVisible(.recents)
            storage = config.isTabVisible(.storage)
        }
    }
}

/// SaveAsDialog of the text editor: file name, extension and folder.
struct SaveAsDialog: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(Config.self) private var config
    @Environment(Storage.self) private var storage
    @Environment(\.palette) private var palette
    let onSave: (String) -> Void
    @State private var name: String
    @State private var ext: String
    @State private var folder: String
    @State private var pickFolder = false
    @State private var error: String?
    @State private var confirmOverwrite: String?

    init(path: String, onSave: @escaping (String) -> Void) {
        self.onSave = onSave
        let path = path.isEmpty ? "\(Storage.internalPath)/\(DateTimeFormat.format(Date(), "yyyy_MM_dd_HH_mm_ss")).txt" : path
        let full = path.filenameFromPath
        let ext = full.fileExtension
        _name = State(initialValue: ext.isEmpty ? full : String(full.dropLast(ext.count + 1)))
        _ext = State(initialValue: ext)
        _folder = State(initialValue: path.parentPath)
    }

    var body: some View {
        DialogFrame(title: "Save as", scroll: false) {
            Button { pickFolder = true } label: {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Folder").font(.system(size: 13)).foregroundStyle(palette.secondaryText)
                    Text(storage.humanize(folder)).foregroundStyle(palette.textColor).lineLimit(2)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, 8)
            }
            .buttonStyle(.plain)
            DialogTextField(placeholder: "Filename", text: $name)
            DialogTextField(placeholder: "Extension", text: $ext)
            if let error { Text(error).font(.system(size: 14)).foregroundStyle(.red) }
            DialogButtons {
                guard !name.isEmpty else { error = "Filename cannot be empty"; return }
                let filename = ext.isEmpty ? name : "\(name).\(ext)"
                guard filename.isAValidFilename else { error = "Filename contains invalid characters"; return }
                let path = "\(folder)/\(filename)"
                if FileManager.default.fileExists(atPath: path) {
                    confirmOverwrite = filename
                } else {
                    dismiss()
                    onSave(path)
                }
            }
        }
        .sheet(isPresented: $pickFolder) {
            FilePickerDialog(path: folder, roots: storage.roots, showFAB: true, canAddShowHiddenButton: true, favorites: config.favorites) { folder = $0 }
        }
        .alert("File \"\(confirmOverwrite ?? "")\" already exists. Overwrite?", isPresented: Binding(get: { confirmOverwrite != nil }, set: { if !$0 { confirmOverwrite = nil } })) {
            Button("No", role: .cancel) {}
            Button("Yes") {
                let path = "\(folder)/\(confirmOverwrite ?? "")"
                dismiss()
                onSave(path)
            }
        }
    }
}

/// SaveAsActivity: a file shared with the app is saved into a picked folder.
struct SaveIncomingDialog: View {
    @Environment(Router.self) private var router
    @Environment(Config.self) private var config
    @Environment(Storage.self) private var storage
    let url: URL

    var body: some View {
        FilePickerDialog(path: config.homeFolder, roots: storage.roots, showHidden: config.shouldShowHidden(), showFAB: true,
                         favorites: config.favorites) { destination in
            router.toast = "Saving…"
            let url = url
            Task.detached {
                let name = Self.sanitize(url.lastPathComponent)
                let target = "\(destination)/\(name)".availablePath
                let accessing = url.startAccessingSecurityScopedResource()
                defer { if accessing { url.stopAccessingSecurityScopedResource() } }
                let ok = (try? FileManager.default.copyItem(atPath: url.path, toPath: target)) != nil
                await MainActor.run { router.toast = ok ? "File saved successfully" : "An unknown error occurred" }
            }
        }
    }

    /// sanitizeFilename().
    nonisolated static func sanitize(_ name: String) -> String {
        let bad = CharacterSet(charactersIn: "/\\<>:\"|?*").union(.controlCharacters)
        let cleaned = String(name.unicodeScalars.map { bad.contains($0) ? "_" : Character($0) })
        return cleaned.trimmingCharacters(in: .whitespaces).isEmpty ? "unnamed_file" : cleaned
    }
}
