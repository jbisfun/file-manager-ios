import FossifyCommons
import Observation
import SwiftUI

/// ItemsFragment state.
@MainActor
@Observable
final class FilesState {
    var path = ""
    var items: [ListItem] = []
    var loading = false
    var searchResults: [ListItem]?
    @ObservationIgnored private var generation = 0
    @ObservationIgnored private var searchGeneration = 0

    /// openPath(): lists the folder in the background, then sorts it.
    func open(_ newPath: String, config: Config) {
        var p = newPath
        while p.count > 1 && p.hasSuffix("/") { p.removeLast() }
        var isDir: ObjCBool = false
        if FileManager.default.fileExists(atPath: p, isDirectory: &isDir) {
            if !isDir.boolValue { p = p.parentPath }
        } else {
            p = Storage.internalPath
        }
        if p != path { items = [] }
        path = p
        reload(config: config)
    }

    func reload(config: Config) {
        generation += 1
        let gen = generation, path = path
        let showHidden = config.shouldShowHidden()
        let sorting = config.getFolderSorting(path)
        let grid = config.getFolderViewType(path) == ViewTypes.grid
        loading = true
        Task.detached {
            let raw = FileOps.items(in: path, showHidden: showHidden, countChildren: !grid, sizeOfFolders: sorting & Sorting.bySize != 0)
            let sorted = FileOps.sorted(raw, sorting: sorting, grid: grid)
            await MainActor.run {
                guard gen == self.generation else { return }
                self.items = sorted
                self.loading = false
            }
        }
    }

    /// searchQueryChanged() of the files tab.
    func search(_ text: String, config: Config, humanize: @escaping (String) -> String) {
        searchGeneration += 1
        let gen = searchGeneration
        guard text.count >= 2 else {
            searchResults = nil
            loading = false
            return
        }
        loading = true
        let path = path, showHidden = config.shouldShowHidden()
        Task.detached {
            let files = FileOps.search(text, in: path, showHidden: showHidden)
            let sections = FileOps.searchSections(files, humanize: humanize)
            await MainActor.run {
                guard gen == self.searchGeneration else { return }
                self.searchResults = sections
                self.loading = false
            }
        }
    }
}

struct MainView: View {
    @Environment(Router.self) private var router
    @Environment(Config.self) private var config
    @Environment(Storage.self) private var storage
    @Environment(\.palette) private var palette

    @State private var tab: MainTab = .files
    @State private var didSetup = false
    @State private var query = ""
    @State private var searching = false
    @FocusState private var searchFocused: Bool

    @State private var files = FilesState()
    @State private var filesActions = ItemActions()
    @State private var recentsActions = ItemActions()
    @State private var storageActions = ItemActions()
    @State private var recents: [ListItem] = []
    @State private var recentsLoaded = false

    @State private var showSorting = false
    @State private var showViewType = false
    @State private var showColumnCount = false
    @State private var showFavorites = false
    @State private var showCreateNew = false
    @State private var showStoragePicker = false

    private var visibleTabs: [MainTab] { MainTab.allCases.filter { config.isTabVisible($0) } }

    private var currentActions: ItemActions {
        switch tab {
        case .files: return filesActions
        case .recents: return recentsActions
        case .storage: return storageActions
        }
    }

    /// currentFragment.currentPath: the folder for the files tab, "" for the others.
    private var currentPath: String { tab == .files ? files.path : "" }

    var body: some View {
        VStack(spacing: 0) {
            if currentActions.isActive {
                SelectionBar(actions: currentActions)
            } else {
                searchBar
            }
            ZStack {
                switch tab {
                case .files: filesPage
                case .recents: recentsPage
                case .storage: StorageTab(query: query, actions: storageActions)
                }
            }
            .frame(maxHeight: .infinity)
            if visibleTabs.count > 1 { bottomTabs }
        }
        .background(palette.backgroundColor.ignoresSafeArea())
        .itemActionSheets(filesActions)
        .itemActionSheets(recentsActions)
        .itemActionSheets(storageActions)
        .onAppear(perform: setup)
        .onChange(of: tab) { _, t in
            config.lastUsedViewPagerPage = visibleTabs.firstIndex(of: t) ?? 0
            closeSearch()
            filesActions.finish()
            recentsActions.finish()
            storageActions.finish()
        }
        .onChange(of: config.showTabs) { _, _ in if !visibleTabs.contains(tab) { tab = visibleTabs.first ?? .files } }
        .onChange(of: query) { _, q in queryChanged(q) }
        .onChange(of: router.openFolder) { _, folder in
            guard let folder else { return }
            router.openFolder = nil
            tab = .files
            files.open(folder, config: config)
        }
        .onChange(of: config.shouldShowHidden()) { _, _ in refreshAll() }
        .onChange(of: config.folderSettingsVersion) { _, _ in refreshAll() }
        .sheet(isPresented: $showSorting) {
            ChangeSortingDialog(path: currentPath)
        }
        .sheet(isPresented: $showViewType) {
            ChangeViewTypeDialog(path: currentPath, showFolderCheck: tab == .files)
        }
        .sheet(isPresented: $showColumnCount) {
            RadioDialog(title: nil, items: (1...maxColumnCount).map { ($0, "\($0) column\($0 == 1 ? "" : "s")") }, selected: config.fileColumnCnt) {
                config.fileColumnCnt = $0
            }
        }
        .sheet(isPresented: $showFavorites) {
            RadioDialog(title: "Go to favorite",
                        items: config.favorites.map { ($0, storage.humanize($0).replacingOccurrences(of: "/", with: " / ")) },
                        selected: files.path) { files.open($0, config: config) }
        }
        .sheet(isPresented: $showCreateNew) {
            CreateNewItemDialog(path: files.path) { ok in
                if ok { files.reload(config: config) } else { router.toast = "An unknown error occurred" }
            }
        }
        .sheet(isPresented: $showStoragePicker) {
            StoragesDialog(current: files.path) { path in
                filesActions.finish()
                files.open(path, config: config)
            }
        }
    }

    // MARK: Pages

    private var filesPage: some View {
        let grid = config.getFolderViewType(files.path) == ViewTypes.grid
        let q = query.trimmingCharacters(in: .whitespaces)
        return ZStack(alignment: .bottomTrailing) {
            VStack(spacing: 0) {
                Breadcrumbs(path: files.path, roots: storage.roots, fontSize: palette.fontSize * 0.9) { index, path in
                    if index == 0 {
                        showStoragePicker = true
                    } else {
                        filesActions.finish()
                        files.open(path, config: config)
                    }
                }
                if files.loading {
                    ProgressView().progressViewStyle(.linear).tint(palette.primaryColor).frame(height: 2)
                }
                if q.count == 1 {
                    Placeholder(text: "No items found.", secondary: "Type in at least 2 characters to start the search.")
                } else if let results = files.searchResults, q.count > 1 {
                    if results.isEmpty {
                        Placeholder(text: "No items found.")
                    } else {
                        ItemsList(items: results, grid: false, highlight: q, actions: filesActions) { item in
                            if item.isSectionTitle {
                                closeSearch()
                                files.open(item.path, config: config)
                            } else {
                                click(item)
                            }
                        }
                    }
                } else {
                    ItemsList(items: files.items, grid: grid, actions: filesActions,
                              refreshable: config.enablePullToRefresh, onRefresh: { files.reload(config: config) }) { click($0) }
                }
            }
            if !filesActions.isActive {
                Fab { showCreateNew = true }.padding(16)
            }
        }
        .onChange(of: files.items) { _, items in filesActions.items = files.searchResults ?? items }
        .onChange(of: files.searchResults) { _, r in filesActions.items = r ?? files.items }
    }

    private var recentsPage: some View {
        let q = query.trimmingCharacters(in: .whitespaces)
        let list = q.isEmpty ? recents : recents.filter { $0.name.normalizedForSearch.localizedCaseInsensitiveContains(q.normalizedForSearch) }
        return Group {
            if list.isEmpty && recentsLoaded {
                Placeholder(text: "No items found.")
            } else {
                ItemsList(items: list, grid: config.getFolderViewType("") == ViewTypes.grid, highlight: q, actions: recentsActions,
                          refreshable: config.enablePullToRefresh && q.isEmpty, onRefresh: { loadRecents() }) { router.open($0.path) }
            }
        }
        .onAppear { recentsActions.items = list }
        .onChange(of: list) { _, l in recentsActions.items = l }
    }

    // MARK: Search menu (MySearchMenu + menu.xml)

    private var searchBar: some View {
        let isFiles = tab == .files
        let grid = config.getFolderViewType(currentPath) == ViewTypes.grid
        let favorites = config.favorites
        return HStack(spacing: 0) {
            if !searching { CloseAppButton() }
            Button {
                if searching { closeSearch() } else {
                    searching = true
                    searchFocused = true
                }
            } label: {
                Image(systemName: searching ? "arrow.left" : "magnifyingglass")
                    .font(.system(size: 18))
                    .frame(width: 48, height: 48)
            }
            TextField("", text: $query, prompt: Text(isFiles ? "Search folder" : "Search").foregroundStyle(palette.secondaryText))
                .focused($searchFocused)
                .submitLabel(.search)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
                .onChange(of: searchFocused) { _, f in if f { searching = true } }
            if !query.isEmpty {
                IconButton(icon: "xmark") { query = "" }
            }
            if isFiles && files.path != config.homeFolder {
                IconButton(icon: "house") { files.open(config.homeFolder, config: config) }
            }
            if isFiles && !favorites.isEmpty {
                IconButton(icon: "star") { showFavorites = true }
            }
            Menu {
                if isFiles {
                    Button { showSorting = true } label: { Label("Sort by", systemImage: "arrow.up.arrow.down") }
                    if favorites.contains(files.path) {
                        Button { config.removeFavorite(files.path) } label: { Label("Remove from favorites", systemImage: "star.slash") }
                    } else {
                        Button { config.addFavorite(files.path) } label: { Label("Add to favorites", systemImage: "star") }
                    }
                }
                if tab != .storage {
                    if grid {
                        Button { config.displayFilenames.toggle() } label: { Label("Toggle filename visibility", systemImage: "textformat") }
                    }
                    Button { showViewType = true } label: { Label("Change view type", systemImage: grid ? "list.bullet" : "square.grid.2x2") }
                }
                if isFiles && files.path != config.homeFolder {
                    Button {
                        config.homeFolder = files.path
                        router.toast = "Home folder updated"
                    } label: { Label("Set as home folder", systemImage: "house") }
                }
                if tab != .storage {
                    if !config.shouldShowHidden() {
                        Button { toggleTemporarilyShowHidden() } label: { Label("Temporarily show hidden", systemImage: "eye") }
                    }
                    if config.temporarilyShowHidden {
                        Button { toggleTemporarilyShowHidden() } label: { Label("Stop showing hidden media", systemImage: "eye.slash") }
                    }
                    if grid {
                        Button { showColumnCount = true } label: { Label("Column count", systemImage: "rectangle.split.3x1") }
                    }
                }
                Button { router.push(.settings) } label: { Label("Settings", systemImage: "gearshape") }
                Button { router.push(.about) } label: { Label("About", systemImage: "info.circle") }
            } label: {
                Image(systemName: "ellipsis")
                    .rotationEffect(.degrees(90))
                    .font(.system(size: 18))
                    .frame(width: 44, height: 48)
            }
        }
        .foregroundStyle(palette.textColor)
        .background(Capsule().fill(palette.surface))
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    // MARK: Tabs

    private var bottomTabs: some View {
        HStack(spacing: 0) {
            ForEach(visibleTabs) { t in
                Button {
                    tab = t
                } label: {
                    VStack(spacing: 4) {
                        Image(systemName: t.icon(selected: t == tab)).font(.system(size: 20))
                        Text(t.title).font(.system(size: 13, weight: t == tab ? .semibold : .regular))
                    }
                    .foregroundStyle(t == tab ? palette.primaryColor : palette.textColor)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .background(palette.surface.ignoresSafeArea(edges: .bottom))
    }

    // MARK: Helpers

    private func setup() {
        guard !didSetup else { return }
        didSetup = true
        if !config.wasStorageAnalysisTabAdded {
            config.wasStorageAnalysisTabAdded = true
            if config.showTabs & MainTab.storage.rawValue == 0 { config.showTabs += MainTab.storage.rawValue }
        }
        config.temporarilyShowHidden = false
        let tabs = visibleTabs
        tab = tabs.indices.contains(config.lastUsedViewPagerPage) ? tabs[config.lastUsedViewPagerPage] : (tabs.first ?? .files)
        filesActions.refresh = { [files, config] in files.reload(config: config) }
        recentsActions.refresh = { loadRecents() }
        files.open(config.homeFolder, config: config)
        loadRecents()
        // checkInvalidFavorites()
        for f in config.favorites where !FileManager.default.fileExists(atPath: f) { config.removeFavorite(f) }
    }

    private func loadRecents() {
        let roots = storage.roots, hidden = config.shouldShowHidden()
        Task.detached {
            let list = FileOps.recents(roots: roots, showHidden: hidden)
            await MainActor.run {
                recents = list
                recentsLoaded = true
            }
        }
    }

    private func refreshAll() {
        files.reload(config: config)
        loadRecents()
    }

    private func click(_ item: ListItem) {
        if item.isDirectory {
            closeSearch()
            files.open(item.path, config: config)
        } else {
            router.open(item.path)
        }
    }

    private func queryChanged(_ q: String) {
        let text = q.trimmingCharacters(in: .whitespaces)
        if tab == .files {
            files.search(text, config: config, humanize: storage.humanize)
        }
    }

    private func closeSearch() {
        query = ""
        searching = false
        searchFocused = false
        files.searchResults = nil
    }

    private func toggleTemporarilyShowHidden() {
        if config.temporarilyShowHidden {
            config.temporarilyShowHidden = false
        } else {
            router.hiddenProtected { config.temporarilyShowHidden = true }
        }
    }
}

/// StoragePickerDialog, plus the folders added from other locations (iOS file providers).
struct StoragesDialog: View {
    @Environment(Storage.self) private var storage
    @Environment(\.palette) private var palette
    @Environment(\.dismiss) private var dismiss
    let current: String
    let onPick: (String) -> Void
    @State private var addFolder = false

    var body: some View {
        DialogFrame(title: "Select storage") {
            let selected = StorageRoot.containing(current, in: storage.roots)?.path
            ForEach(storage.roots) { root in
                HStack {
                    Button {
                        onPick(root.path)
                        dismiss()
                    } label: { RadioRow(title: root.title, on: root.path == selected) }
                    .buttonStyle(.plain)
                    if root.path != Storage.internalPath {
                        IconButton(icon: "xmark") { storage.removeFolder(root.path) }
                    }
                }
            }
            Button { addFolder = true } label: {
                HStack(spacing: 16) {
                    Image(systemName: "plus.circle").font(.system(size: 20)).foregroundStyle(palette.primaryColor)
                    Text("Add a folder from another location").foregroundStyle(palette.primaryColor)
                    Spacer()
                }
                .padding(.vertical, 12)
            }
            .buttonStyle(.plain)
        }
        .sheet(isPresented: $addFolder) {
            FolderPicker { url in
                storage.addFolder(url)
                onPick(url.path)
                dismiss()
            }
        }
    }
}
