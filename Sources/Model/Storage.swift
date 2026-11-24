import FossifyCommons
import Foundation
import Observation

/// The storages the app can browse: its own Documents folder ("Internal", shared with
/// the Files app) plus folders the user added from other locations (iCloud Drive, On My
/// iPhone, USB drives, file providers), kept as security-scoped bookmarks.
@Observable
final class Storage {
    static let shared = Storage()

    static let internalPath: String = {
        let url = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        return url.path.hasSuffix("/") ? String(url.path.dropLast()) : url.path
    }()

    private static let placeholder = "{internal}"
    @ObservationIgnored private let d = UserDefaults.standard
    @ObservationIgnored private var accessed: [URL] = []

    /// Added folders: (bookmark, resolved path).
    private(set) var external: [(Data, String)] = []

    private init() {
        for data in d.array(forKey: "storage_bookmarks") as? [Data] ?? [] {
            var stale = false
            guard let url = try? URL(resolvingBookmarkData: data, bookmarkDataIsStale: &stale) else { continue }
            if url.startAccessingSecurityScopedResource() { accessed.append(url) }
            let fresh = stale ? ((try? url.bookmarkData()) ?? data) : data
            external.append((fresh, url.path.hasSuffix("/") ? String(url.path.dropLast()) : url.path))
        }
        save()
    }

    var roots: [StorageRoot] {
        [StorageRoot(path: Storage.internalPath, title: "Internal")] + external.map { StorageRoot(path: $0.1, title: $0.1.filenameFromPath) }
    }

    func addFolder(_ url: URL) {
        let accessing = url.startAccessingSecurityScopedResource()
        guard let data = try? url.bookmarkData() else {
            if accessing { url.stopAccessingSecurityScopedResource() }
            return
        }
        if accessing { accessed.append(url) }
        let path = url.path.hasSuffix("/") ? String(url.path.dropLast()) : url.path
        guard !external.contains(where: { $0.1 == path }) else { return }
        external.append((data, path))
        save()
    }

    func removeFolder(_ path: String) {
        external.removeAll { $0.1 == path }
        save()
    }

    private func save() { d.set(external.map(\.0), forKey: "storage_bookmarks") }

    func humanize(_ path: String) -> String { StorageRoot.humanize(path, in: roots) }

    static func portable(_ path: String) -> String {
        path.hasPrefix(internalPath) ? placeholder + path.dropFirst(internalPath.count) : path
    }

    static func absolute(_ path: String) -> String {
        path.hasPrefix(placeholder) ? internalPath + path.dropFirst(placeholder.count) : path
    }

    /// Volume capacity (StorageStatsManager.getTotalBytes / getFreeBytes).
    static func capacity() -> (total: Int64, free: Int64) {
        let url = URL(fileURLWithPath: internalPath)
        let values = try? url.resourceValues(forKeys: [.volumeTotalCapacityKey, .volumeAvailableCapacityForImportantUsageKey])
        return (Int64(values?.volumeTotalCapacity ?? 0), values?.volumeAvailableCapacityForImportantUsage ?? 0)
    }
}
