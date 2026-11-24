import FossifyCommons
import Observation
import SwiftUI

/// Bottom tabs (TAB_FILES / TAB_RECENT_FILES / TAB_STORAGE_ANALYSIS).
enum MainTab: Int, CaseIterable, Identifiable {
    case files = 16, recents = 32, storage = 64

    static let allMask = 16 | 32 | 64
    var id: Int { rawValue }

    var title: String {
        switch self {
        case .files: return "Files"
        case .recents: return "Recents"
        case .storage: return "Storage"
        }
    }

    func icon(selected: Bool) -> String {
        switch self {
        case .files: return selected ? "folder.fill" : "folder"
        case .recents: return selected ? "clock.fill" : "clock"
        case .storage: return "internaldrive"
        }
    }
}

/// Port of the file manager Config plus the BaseConfig values it uses (SharedPreferences -> UserDefaults).
/// Paths are stored with the app's Documents folder replaced by a placeholder, as iOS moves
/// the app container on updates. Colors and font size live in FossifyCommons.BaseConfig.
@Observable
final class Config {
    static let shared = Config()

    @ObservationIgnored private let d = UserDefaults.standard

    var showHidden: Bool { didSet { d.set(showHidden, forKey: "show_hidden") } }
    var temporarilyShowHidden: Bool { didSet { d.set(temporarilyShowHidden, forKey: "temporarily_show_hidden") } }
    var editorTextZoom: Double { didSet { d.set(editorTextZoom, forKey: "editor_text_zoom") } }
    var displayFilenames: Bool { didSet { d.set(displayFilenames, forKey: "display_file_names") } }
    var showTabs: Int { didSet { d.set(showTabs, forKey: "show_tabs") } }
    var wasStorageAnalysisTabAdded: Bool { didSet { d.set(wasStorageAnalysisTabAdded, forKey: "was_storage_analysis_tab_added") } }
    var lastUsedViewPagerPage: Int { didSet { d.set(lastUsedViewPagerPage, forKey: "last_used_view_pager_page") } }

    // BaseConfig
    var sorting: Int { didSet { d.set(sorting, forKey: "sort_order") } }
    var viewType: Int { didSet { d.set(viewType, forKey: "view_type") } }
    var enablePullToRefresh: Bool { didSet { d.set(enablePullToRefresh, forKey: "enable_pull_to_refresh") } }
    var skipDeleteConfirmation: Bool { didSet { d.set(skipDeleteConfirmation, forKey: "skip_delete_confirmation") } }
    var keepLastModified: Bool { didSet { d.set(keepLastModified, forKey: "keep_last_modified") } }

    private var storedHomeFolder: String { didSet { d.set(storedHomeFolder, forKey: "home_folder") } }
    private var storedFavorites: [String] { didSet { d.set(storedFavorites, forKey: "favorites") } }
    private var storedLastCopyPath: String { didSet { d.set(storedLastCopyPath, forKey: "last_copy_path") } }
    private var fileColumnCntPortrait: Int { didSet { d.set(fileColumnCntPortrait, forKey: "file_column_cnt") } }
    private var fileColumnCntLandscape: Int { didSet { d.set(fileColumnCntLandscape, forKey: "file_landscape_column_cnt") } }

    /// Bumped whenever a per-folder sorting or view type changes.
    private(set) var folderSettingsVersion = 0
    /// Set from the root view's geometry; picks the portrait or landscape column count.
    var isLandscape = false

    private init() {
        showHidden = d.bool(forKey: "show_hidden")
        temporarilyShowHidden = d.bool(forKey: "temporarily_show_hidden")
        editorTextZoom = d.object(forKey: "editor_text_zoom") as? Double ?? 1.2
        displayFilenames = d.object(forKey: "display_file_names") as? Bool ?? true
        showTabs = d.object(forKey: "show_tabs") as? Int ?? MainTab.allMask
        wasStorageAnalysisTabAdded = d.bool(forKey: "was_storage_analysis_tab_added")
        lastUsedViewPagerPage = d.integer(forKey: "last_used_view_pager_page")
        sorting = d.object(forKey: "sort_order") as? Int ?? (Sorting.byName | Sorting.useNumericValue)
        viewType = d.object(forKey: "view_type") as? Int ?? ViewTypes.list
        enablePullToRefresh = d.object(forKey: "enable_pull_to_refresh") as? Bool ?? true
        skipDeleteConfirmation = d.bool(forKey: "skip_delete_confirmation")
        keepLastModified = d.object(forKey: "keep_last_modified") as? Bool ?? true
        storedHomeFolder = d.string(forKey: "home_folder") ?? ""
        storedFavorites = d.stringArray(forKey: "favorites") ?? []
        storedLastCopyPath = d.string(forKey: "last_copy_path") ?? ""
        fileColumnCntPortrait = d.object(forKey: "file_column_cnt") as? Int ?? 4
        fileColumnCntLandscape = d.object(forKey: "file_landscape_column_cnt") as? Int ?? 8
    }

    func shouldShowHidden() -> Bool { showHidden || temporarilyShowHidden }

    var homeFolder: String {
        get {
            let path = Storage.absolute(storedHomeFolder)
            var isDir: ObjCBool = false
            if storedHomeFolder.isEmpty || !FileManager.default.fileExists(atPath: path, isDirectory: &isDir) || !isDir.boolValue {
                return Storage.internalPath
            }
            return path
        }
        set { storedHomeFolder = Storage.portable(newValue) }
    }

    var lastCopyPath: String {
        get { Storage.absolute(storedLastCopyPath) }
        set { storedLastCopyPath = Storage.portable(newValue) }
    }

    var favorites: [String] { storedFavorites.map(Storage.absolute) }

    func addFavorite(_ path: String) {
        let p = Storage.portable(path)
        if !storedFavorites.contains(p) { storedFavorites.append(p) }
    }

    func removeFavorite(_ path: String) { storedFavorites.removeAll { $0 == Storage.portable(path) } }

    func moveFavorite(_ old: String, _ new: String) {
        guard let i = storedFavorites.firstIndex(of: Storage.portable(old)) else { return }
        storedFavorites[i] = Storage.portable(new)
    }

    var fileColumnCnt: Int {
        get { isLandscape ? fileColumnCntLandscape : fileColumnCntPortrait }
        set {
            let v = max(1, min(maxColumnCount, newValue))
            if isLandscape { fileColumnCntLandscape = v } else { fileColumnCntPortrait = v }
        }
    }

    // Per-folder sorting (sort_folder_) and view type (view_type_folder_). Pseudo-folders
    // ("" for Recents/Storage, mime type names) use the same keys like upstream.

    private func folderKey(_ prefix: String, _ path: String) -> String { prefix + Storage.portable(path).lowercased() }

    func getFolderSorting(_ path: String) -> Int {
        _ = folderSettingsVersion
        return d.object(forKey: folderKey("sort_folder_", path)) as? Int ?? sorting
    }

    func hasCustomSorting(_ path: String) -> Bool { d.object(forKey: folderKey("sort_folder_", path)) != nil }

    func saveCustomSorting(_ path: String, _ value: Int) {
        if path.isEmpty { sorting = value } else { d.set(value, forKey: folderKey("sort_folder_", path)) }
        folderSettingsVersion += 1
    }

    func removeCustomSorting(_ path: String) {
        d.removeObject(forKey: folderKey("sort_folder_", path))
        folderSettingsVersion += 1
    }

    func getFolderViewType(_ path: String) -> Int {
        _ = folderSettingsVersion
        return d.object(forKey: folderKey("view_type_folder_", path)) as? Int ?? viewType
    }

    func hasCustomViewType(_ path: String) -> Bool { d.object(forKey: folderKey("view_type_folder_", path)) != nil }

    func saveFolderViewType(_ path: String, _ value: Int) {
        if path.isEmpty { viewType = value } else { d.set(value, forKey: folderKey("view_type_folder_", path)) }
        folderSettingsVersion += 1
    }

    func removeFolderViewType(_ path: String) {
        d.removeObject(forKey: folderKey("view_type_folder_", path))
        folderSettingsVersion += 1
    }

    func isTabVisible(_ tab: MainTab) -> Bool { showTabs & tab.rawValue != 0 }
}

/// MAX_COLUMN_COUNT.
let maxColumnCount = 15
