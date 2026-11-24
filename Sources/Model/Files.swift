import FossifyCommons
import Foundation
import UniformTypeIdentifiers

/// models.ListItem: a FileDirItem that can also be a search-results section title or the
/// grid divider between folders and files.
struct ListItem: Identifiable, Hashable {
    var item: FileDirItem
    var isSectionTitle = false
    var isGridTypeDivider = false

    var id: String { isGridTypeDivider ? "\u{0}divider" : (isSectionTitle ? "\u{0}section:" + item.path : item.path) }
    var path: String { item.path }
    var name: String { item.name }
    var isDirectory: Bool { item.isDirectory }

    static let divider = ListItem(item: FileDirItem(path: "", name: ""), isGridTypeDivider: true)
}

/// Storage analysis categories (IMAGES / VIDEOS / AUDIO / DOCUMENTS / ARCHIVES / OTHERS).
enum FileCategory: String, CaseIterable, Identifiable, Hashable {
    case images, videos, audio, documents, archives, others

    var id: String { rawValue }

    var title: String {
        switch self {
        case .images: return "Images"
        case .videos: return "Videos"
        case .audio: return "Audio"
        case .documents: return "Documents"
        case .archives: return "Archives"
        case .others: return "Others"
        }
    }

    var icon: String {
        switch self {
        case .images: return "photo"
        case .videos: return "film"
        case .audio: return "music.note"
        case .documents: return "doc.text"
        case .archives: return "doc.zipper"
        case .others: return "doc"
        }
    }

    /// md_red_700, md_green_700, md_light_blue_700, md_yellow_700, md_teal_700, md_pink_700.
    var color: UInt32 {
        switch self {
        case .images: return 0xFFD32F2F
        case .videos: return 0xFF388E3C
        case .audio: return 0xFF0288D1
        case .documents: return 0xFFFBC02D
        case .archives: return 0xFF00796B
        case .others: return 0xFFC2185B
        }
    }

    /// MIME type buckets of StorageFragment.getSizesByMimeType(), on UTTypes.
    static func of(_ path: String) -> FileCategory {
        let ext = path.fileExtension.lowercased()
        guard let type = UTType(filenameExtension: ext) else { return .others }
        if type.conforms(to: .image) { return .images }
        if type.conforms(to: .audio) || ext == "ogg" { return .audio }
        if type.conforms(to: .movie) || type.conforms(to: .video) { return .videos }
        if type.conforms(to: .archive) || type.conforms(to: .zip) || ["zip", "tar", "rar", "7z", "gz", "jar", "json"].contains(ext) { return .archives }
        if type.conforms(to: .text) || type.conforms(to: .pdf) || ["doc", "docx", "xlsx", "js"].contains(ext) { return .documents }
        return .others
    }
}

extension String {
    /// isZipFile().
    var isZipFile: Bool { lowercased().hasSuffix(".zip") }

    /// isPathInHiddenFolder().
    var isPathInHiddenFolder: Bool {
        let parts = split(separator: "/", omittingEmptySubsequences: false)
        guard parts.count > 2 else { return false }
        return parts[1..<(parts.count - 1)].contains { $0.hasPrefix(".") && $0 != "." && $0 != ".." }
    }

    /// Files the app opens itself instead of previewing them (text editor).
    var isTextFile: Bool {
        guard let type = UTType(filenameExtension: fileExtension.lowercased()) else { return false }
        return type.conforms(to: .text) && !type.conforms(to: .rtf) && !type.conforms(to: .html) || type.conforms(to: .sourceCode)
            || type.conforms(to: .json) || type.conforms(to: .xml) || type.conforms(to: .propertyList)
    }
}

/// File system work done by the fragments, ItemsAdapter and the activities.
enum FileOps {
    /// ItemsFragment.getRegularItemsOf().
    static func items(in path: String, showHidden: Bool, countChildren: Bool, sizeOfFolders: Bool) -> [ListItem] {
        let names = (try? FileManager.default.contentsOfDirectory(atPath: path)) ?? []
        let base = path == "/" ? "" : path
        return names.compactMap { name -> ListItem? in
            if !showHidden && name.hasPrefix(".") { return nil }
            guard var item = FileDirItem(path: "\(base)/\(name)", countChildren: countChildren, countHidden: showHidden) else { return nil }
            if item.isDirectory && sizeOfFolders { item.size = FileDirItem.properSize(item.path, countHidden: showHidden) }
            return ListItem(item: item)
        }
    }

    /// ItemsFragment.openPath(): sorted, with a divider between folders and files in grids.
    static func sorted(_ items: [ListItem], sorting: Int, grid: Bool) -> [ListItem] {
        var list = items.sorted { FileDirItem.areInIncreasingOrder($0.item, $1.item, sorting: sorting) }
        if grid, list.contains(where: \.isDirectory), let first = list.firstIndex(where: { !$0.isDirectory }) {
            list.insert(.divider, at: first)
        }
        return list
    }

    /// ItemsFragment.searchFiles(): recursive name search.
    static func search(_ text: String, in path: String, showHidden: Bool) -> [ListItem] {
        let needle = text.normalizedForSearch
        var result: [ListItem] = []
        FileDirItem.walk(path, countHidden: showHidden) { p, isDir, _ in
            if p.filenameFromPath.normalizedForSearch.localizedCaseInsensitiveContains(needle), let item = FileDirItem(path: p) {
                result.append(ListItem(item: item))
            }
            _ = isDir
        }
        return result
    }

    /// Search results grouped by folder with section titles (ItemsFragment.searchQueryChanged).
    static func searchSections(_ files: [ListItem], humanize: (String) -> String) -> [ListItem] {
        let sorted = files.sorted { $0.item.parentPath.localizedStandardCompare($1.item.parentPath) == .orderedAscending }
        var list: [ListItem] = []
        var previousParent = ""
        for f in sorted {
            let parent = f.item.parentPath
            if !f.isDirectory && parent != previousParent {
                list.append(ListItem(item: FileDirItem(path: parent, name: humanize(parent)), isSectionTitle: true))
                previousParent = parent
            }
            if f.isDirectory {
                list.append(ListItem(item: FileDirItem(path: f.path, name: humanize(f.path), isDirectory: true), isSectionTitle: true))
                previousParent = parent
            } else {
                list.append(f)
            }
        }
        return list
    }

    /// Every file on all storages (MediaStore.Files stand-in), newest first.
    static func allFiles(roots: [StorageRoot], showHidden: Bool) -> [ListItem] {
        var result: [ListItem] = []
        for root in roots {
            FileDirItem.walk(root.path, countHidden: showHidden) { p, isDir, size in
                guard !isDir, size > 0, let item = FileDirItem(path: p) else { return }
                result.append(ListItem(item: item))
            }
        }
        return result.sorted { $0.item.modified > $1.item.modified }
    }

    /// RecentsFragment.getRecents(): the 50 most recently modified files.
    static func recents(roots: [StorageRoot], showHidden: Bool) -> [ListItem] {
        var result: [ListItem] = []
        for root in roots {
            FileDirItem.walk(root.path, countHidden: showHidden) { p, isDir, _ in
                guard !isDir, let item = FileDirItem(path: p) else { return }
                result.append(ListItem(item: item))
            }
        }
        return Array(result.sorted { $0.item.modified > $1.item.modified }.prefix(50))
    }

    /// StorageFragment.getSizesByMimeType().
    static func categorySizes(roots: [StorageRoot]) -> [FileCategory: Int64] {
        var sizes: [FileCategory: Int64] = [:]
        for root in roots {
            FileDirItem.walk(root.path, countHidden: true) { p, isDir, size in
                guard !isDir else { return }
                sizes[FileCategory.of(p), default: 0] += size
            }
        }
        return sizes
    }

    /// MimeTypesActivity.getProperFileDirItems().
    static func files(of category: FileCategory, roots: [StorageRoot], showHidden: Bool) -> [ListItem] {
        var result: [ListItem] = []
        for root in roots {
            FileDirItem.walk(root.path, countHidden: showHidden) { p, isDir, size in
                guard !isDir, size > 0, FileCategory.of(p) == category, let item = FileDirItem(path: p) else { return }
                result.append(ListItem(item: item))
            }
        }
        return result
    }

    /// toggleItemVisibility(): hiding = adding a leading dot.
    @discardableResult
    static func toggleVisibility(_ path: String, hide: Bool) -> String {
        let name = path.filenameFromPath
        if hide == name.hasPrefix(".") { return path }
        let newName = hide ? "." + name.drop { $0 == "." } : String(name.dropFirst())
        let newPath = "\(path.parentPath)/\(newName)"
        return FileRename.rename(path, to: newPath) ? newPath : path
    }

    /// deleteFiles(): returns false if anything failed.
    static func delete(_ paths: [String]) -> Bool {
        var ok = true
        for p in paths where (try? FileManager.default.removeItem(atPath: p)) == nil { ok = false }
        return ok
    }

    /// CopyMoveTask: copies or moves items into `destination`, honoring conflict resolutions.
    /// Returns how many top-level items succeeded.
    static func copyMove(_ items: [FileDirItem], to destination: String, copy: Bool, resolutions: [String: ConflictResolution],
                         keepLastModified: Bool, copyHidden: Bool) -> Int {
        var done = 0
        for item in items {
            let target = "\(destination)/\(item.name)"
            if item.path == target { continue }
            var dest = target
            if FileManager.default.fileExists(atPath: target) {
                switch ConflictCheck.resolution(for: target, in: resolutions) {
                case .skip: continue
                case .overwrite: try? FileManager.default.removeItem(atPath: target)
                case .keepBoth: dest = target.availablePath
                case .merge:
                    if item.isDirectory && merge(item.path, into: target, copy: copy, keepLastModified: keepLastModified, copyHidden: copyHidden) {
                        done += 1
                    }
                    continue
                }
            }
            if transfer(item.path, to: dest, copy: copy, keepLastModified: keepLastModified, copyHidden: copyHidden) { done += 1 }
        }
        return done
    }

    private static func merge(_ source: String, into target: String, copy: Bool, keepLastModified: Bool, copyHidden: Bool) -> Bool {
        var ok = true
        for name in (try? FileManager.default.contentsOfDirectory(atPath: source)) ?? [] {
            if !copyHidden && name.hasPrefix(".") { continue }
            let s = "\(source)/\(name)", t = "\(target)/\(name)"
            var sDir: ObjCBool = false, tDir: ObjCBool = false
            FileManager.default.fileExists(atPath: s, isDirectory: &sDir)
            if FileManager.default.fileExists(atPath: t, isDirectory: &tDir) {
                if sDir.boolValue && tDir.boolValue {
                    ok = merge(s, into: t, copy: copy, keepLastModified: keepLastModified, copyHidden: copyHidden) && ok
                    continue
                }
                try? FileManager.default.removeItem(atPath: t)
            }
            ok = transfer(s, to: t, copy: copy, keepLastModified: keepLastModified, copyHidden: copyHidden) && ok
        }
        if !copy && ok { try? FileManager.default.removeItem(atPath: source) }
        return ok
    }

    private static func transfer(_ source: String, to dest: String, copy: Bool, keepLastModified: Bool, copyHidden: Bool) -> Bool {
        do {
            if copy {
                try FileManager.default.copyItem(atPath: source, toPath: dest)
                if !copyHidden { removeHidden(in: dest) }
                if !keepLastModified { touch(dest) }
            } else {
                try FileManager.default.moveItem(atPath: source, toPath: dest)
                if !keepLastModified { touch(dest) }
            }
            return true
        } catch {
            return false
        }
    }

    private static func removeHidden(in path: String) {
        var hidden: [String] = []
        FileDirItem.walk(path, countHidden: true) { p, _, _ in if p.filenameFromPath.hasPrefix(".") { hidden.append(p) } }
        for p in hidden { try? FileManager.default.removeItem(atPath: p) }
    }

    private static func touch(_ path: String) {
        try? FileManager.default.setAttributes([.modificationDate: Date()], ofItemAtPath: path)
        FileDirItem.walk(path, countHidden: true) { p, _, _ in
            try? FileManager.default.setAttributes([.modificationDate: Date()], ofItemAtPath: p)
        }
    }

    /// CreateNewItemDialog.
    static func create(_ path: String, folder: Bool) -> Bool {
        if folder {
            return (try? FileManager.default.createDirectory(atPath: path, withIntermediateDirectories: true)) != nil
        }
        return FileManager.default.createFile(atPath: path, contents: Data())
    }

    /// ItemsAdapter.addFileUris(): files inside selected folders, recursively.
    static func shareURLs(_ paths: [String], showHidden: Bool) -> [URL] {
        var urls: [URL] = []
        for p in paths {
            var isDir: ObjCBool = false
            FileManager.default.fileExists(atPath: p, isDirectory: &isDir)
            if isDir.boolValue {
                FileDirItem.walk(p, countHidden: showHidden) { f, d, _ in if !d { urls.append(URL(fileURLWithPath: f)) } }
            } else {
                urls.append(URL(fileURLWithPath: p))
            }
        }
        return urls
    }
}

/// Zip support (zip4j in the original), on ZIPFoundation.
enum Zip {
    struct EntryInfo: Hashable {
        var path: String
        var isDirectory: Bool
        var modified: Date
    }

    enum Failure: Error {
        case encrypted, unreadable
    }

    /// ItemsAdapter.compressPaths(): folders are added recursively, named relative to their parent.
    static func compress(_ paths: [String], to target: String) -> Bool {
        do {
            let archive = try Archive(url: URL(fileURLWithPath: target), accessMode: .create)
            for path in paths {
                let base = URL(fileURLWithPath: path.parentPath)
                let name = path.filenameFromPath
                try archive.addEntry(with: name, relativeTo: base, compressionMethod: .deflate)
                var isDir: ObjCBool = false
                FileManager.default.fileExists(atPath: path, isDirectory: &isDir)
                if isDir.boolValue {
                    var nested: [String] = []
                    FileDirItem.walk(path, countHidden: true) { p, _, _ in nested.append(p) }
                    for p in nested {
                        try archive.addEntry(with: name + String(p.dropFirst(path.count)), relativeTo: base, compressionMethod: .deflate)
                    }
                }
            }
            return true
        } catch {
            try? FileManager.default.removeItem(atPath: target)
            return false
        }
    }

    /// DecompressActivity.fillAllListItems().
    static func entries(_ path: String) throws -> [EntryInfo] {
        let archive = try Archive(url: URL(fileURLWithPath: path), accessMode: .read)
        var result: [EntryInfo] = []
        for entry in archive {
            if entry.centralDirectoryStructure.generalPurposeBitFlag & 1 != 0 { throw Failure.encrypted }
            let p = entry.path.hasSuffix("/") ? String(entry.path.dropLast()) : entry.path
            result.append(EntryInfo(path: p, isDirectory: entry.type == .directory,
                                    modified: entry.fileAttributes[.modificationDate] as? Date ?? Date()))
        }
        // Archives without folder entries still show their folders.
        let known = Set(result.map(\.path))
        var implied = Set<String>()
        for e in result {
            var parent = e.path
            while let slash = parent.lastIndex(of: "/") {
                parent = String(parent[..<slash])
                if !known.contains(parent) { implied.insert(parent) }
            }
        }
        result += implied.map { EntryInfo(path: $0, isDirectory: true, modified: Date()) }
        return result
    }

    /// Extracts the whole archive into `folder` (created if needed), skipping entries that
    /// would escape it. Top-level items that already exist are skipped, replaced, merged
    /// into or kept next to according to `resolutions` (see ConflictCheck).
    static func extract(_ path: String, into folder: String, resolutions: [String: ConflictResolution] = ["": .merge]) throws {
        let archive = try Archive(url: URL(fileURLWithPath: path), accessMode: .read)
        let root = URL(fileURLWithPath: folder).standardizedFileURL
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        var folders: [(URL, Date)] = []
        var tops: [String: String] = [:] // existing top-level name -> name to extract under ("" = skip)
        for entry in archive {
            if entry.centralDirectoryStructure.generalPurposeBitFlag & 1 != 0 { throw Failure.encrypted }
            var name = entry.path.hasSuffix("/") ? String(entry.path.dropLast()) : entry.path
            let top = String(name.split(separator: "/").first ?? "")
            if tops[top] == nil && FileManager.default.fileExists(atPath: root.path + "/" + top) {
                let topPath = root.path + "/" + top
                switch ConflictCheck.resolution(for: topPath, in: resolutions) {
                case .skip: tops[top] = ""
                case .overwrite:
                    try? FileManager.default.removeItem(atPath: topPath)
                    tops[top] = top
                case .merge: tops[top] = top
                case .keepBoth: tops[top] = topPath.availablePath.filenameFromPath
                }
            } else if tops[top] == nil {
                tops[top] = top
            }
            guard let mapped = tops[top], !mapped.isEmpty else { continue }
            name = mapped + name.dropFirst(top.count)
            let url = root.appendingPathComponent(name).standardizedFileURL
            guard url.path.hasPrefix(root.path + "/") else { continue }
            let modified = entry.fileAttributes[.modificationDate] as? Date ?? Date()
            if entry.type == .directory {
                try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
                folders.append((url, modified))
                continue
            }
            if FileManager.default.fileExists(atPath: url.path) {
                try? FileManager.default.removeItem(at: url)
            }
            _ = try archive.extract(entry, to: url)
            try? FileManager.default.setAttributes([.modificationDate: modified], ofItemAtPath: url.path)
        }
        for (url, date) in folders.reversed() {
            try? FileManager.default.setAttributes([.modificationDate: date], ofItemAtPath: url.path)
        }
    }

    /// Top-level items an extraction into `folder` would create (for the conflict check).
    static func topLevelItems(_ path: String, folder: String) -> [FileDirItem] {
        guard let entries = try? entries(path) else { return [] }
        let names = Set(entries.map { String($0.path.split(separator: "/").first ?? "") }).filter { !$0.isEmpty }
        return names.map { n in
            FileDirItem(path: "\(folder)/\(n)", isDirectory: entries.contains { $0.path == n && $0.isDirectory } || entries.contains { $0.path.hasPrefix(n + "/") })
        }
    }
}
