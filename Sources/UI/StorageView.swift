import FossifyCommons
import SwiftUI

/// StorageFragment: storage usage by file type, and search across every file.
struct StorageTab: View {
    @Environment(Router.self) private var router
    @Environment(Config.self) private var config
    @Environment(Storage.self) private var storage
    @Environment(\.palette) private var palette
    let query: String
    let actions: ItemActions

    @State private var total: Int64 = 0
    @State private var free: Int64 = 0
    @State private var sizes: [FileCategory: Int64]?
    @State private var allFiles: [ListItem] = []
    @State private var results: [ListItem] = []
    @State private var searching = false

    var body: some View {
        let q = query.trimmingCharacters(in: .whitespaces)
        ZStack {
            ScrollView {
                volumeCard.padding(16)
            }
            if !q.isEmpty {
                Group {
                    if q.count == 1 {
                        Placeholder(text: "No items found.", secondary: "Type in at least 2 characters to start the search.")
                    } else if results.isEmpty && !searching {
                        Placeholder(text: "No items found.")
                    } else {
                        ItemsList(items: results, grid: config.getFolderViewType("") == ViewTypes.grid, highlight: q, actions: actions) {
                            router.open($0.path)
                        }
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(palette.backgroundColor)
                .transition(.opacity)
            }
            if searching {
                VStack { ProgressView().progressViewStyle(.linear).tint(palette.primaryColor); Spacer() }
            }
        }
        .animation(.default, value: q.isEmpty)
        .task { await load() }
        .onChange(of: q) { _, text in search(text) }
        .onChange(of: results) { _, r in actions.items = r }
        .onAppear { actions.refresh = { Task { await load(); search(query.trimmingCharacters(in: .whitespaces)) } } }
    }

    private var volumeCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Internal").font(.system(size: palette.fontSize, weight: .semibold))
            ProgressView(value: Double(max(0, total - free)), total: Double(max(total, 1)))
                .tint(palette.primaryColor)
                .opacity(total > 0 ? 1 : 0)
            HStack(alignment: .firstTextBaseline) {
                Text(total > 0 ? free.formattedSize : "…").font(.system(size: palette.fontSize * 1.3, weight: .medium))
                Text("free").foregroundStyle(palette.secondaryText)
                Spacer()
                Text("Total storage: \(total > 0 ? total.formattedSize : "…")").font(.system(size: palette.fontSize * 0.8)).foregroundStyle(palette.secondaryText)
            }
            ForEach(FileCategory.allCases) { category in
                Button { router.push(.mimeTypes(category)) } label: {
                    HStack(spacing: 16) {
                        Image(systemName: category.icon)
                            .font(.system(size: 20))
                            .foregroundStyle(Color(argb: category.color))
                            .frame(width: 32)
                        VStack(alignment: .leading, spacing: 6) {
                            HStack {
                                Text(category.title).font(.system(size: palette.fontSize * 0.9))
                                Spacer()
                                Text(sizes.map { ($0[category] ?? 0).formattedSize } ?? "…")
                                    .font(.system(size: palette.fontSize * 0.8)).foregroundStyle(palette.secondaryText)
                            }
                            ProgressView(value: Double(sizes?[category] ?? 0), total: Double(max(total, 1)))
                                .tint(Color(argb: category.color))
                        }
                    }
                    .padding(.vertical, 8)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(16)
        .background(RoundedRectangle(cornerRadius: 16).fill(palette.surface))
    }

    private func load() async {
        let cap = Storage.capacity()
        total = cap.total
        free = cap.free
        let roots = storage.roots, hidden = config.shouldShowHidden()
        let (s, files) = await Task.detached {
            (FileOps.categorySizes(roots: roots), FileOps.allFiles(roots: roots, showHidden: hidden))
        }.value
        sizes = s
        allFiles = files
    }

    private func search(_ text: String) {
        guard text.count > 1 else {
            results = []
            return
        }
        searching = true
        let all = allFiles
        Task.detached {
            let needle = text.normalizedForSearch
            let filtered = all.filter { $0.name.normalizedForSearch.localizedCaseInsensitiveContains(needle) }
            await MainActor.run {
                if text == query.trimmingCharacters(in: .whitespaces) { results = filtered }
                searching = false
            }
        }
    }
}

/// MimeTypesActivity: every file of one storage analysis category.
struct MimeTypesView: View {
    @Environment(Router.self) private var router
    @Environment(Config.self) private var config
    @Environment(Storage.self) private var storage
    @Environment(\.palette) private var palette
    let category: FileCategory

    @State private var stored: [ListItem] = []
    @State private var loaded = false
    @State private var query = ""
    @State private var searching = false
    @FocusState private var searchFocused: Bool
    @State private var actions = ItemActions()
    @State private var showSorting = false
    @State private var showViewType = false
    @State private var showColumnCount = false

    var body: some View {
        let key = category.rawValue
        let grid = config.getFolderViewType(key) == ViewTypes.grid
        let sorting = config.getFolderSorting(key)
        let q = query.trimmingCharacters(in: .whitespaces)
        let sorted = stored.sorted { FileDirItem.areInIncreasingOrder($0.item, $1.item, sorting: sorting) }
        let list = q.count < 2 ? sorted : sorted.filter { $0.name.normalizedForSearch.localizedCaseInsensitiveContains(q.normalizedForSearch) }
        VStack(spacing: 0) {
            if actions.isActive {
                SelectionBar(actions: actions)
            } else if searching {
                HStack(spacing: 0) {
                    IconButton(icon: "arrow.left") {
                        query = ""
                        searching = false
                    }
                    TextField("", text: $query, prompt: Text("Search").foregroundStyle(palette.secondaryText))
                        .focused($searchFocused)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                    if !query.isEmpty { IconButton(icon: "xmark") { query = "" } }
                }
                .frame(height: 56)
                .onAppear { searchFocused = true }
            } else {
                TopBar(title: category.title, onBack: { router.pop() }, background: nil, tint: nil) {
                    IconButton(icon: "magnifyingglass") { searching = true }
                    Menu {
                        Button { showSorting = true } label: { Label("Sort by", systemImage: "arrow.up.arrow.down") }
                        if grid {
                            Button { config.displayFilenames.toggle() } label: { Label("Toggle filename visibility", systemImage: "textformat") }
                        }
                        Button { showViewType = true } label: { Label("Change view type", systemImage: grid ? "list.bullet" : "square.grid.2x2") }
                        if !config.shouldShowHidden() {
                            Button { toggleHidden() } label: { Label("Temporarily show hidden", systemImage: "eye") }
                        }
                        if config.temporarilyShowHidden {
                            Button { toggleHidden() } label: { Label("Stop showing hidden media", systemImage: "eye.slash") }
                        }
                        if grid {
                            Button { showColumnCount = true } label: { Label("Column count", systemImage: "rectangle.split.3x1") }
                        }
                    } label: {
                        Image(systemName: "ellipsis").rotationEffect(.degrees(90)).font(.system(size: 18)).frame(width: 44, height: 48)
                    }
                }
            }
            if q.count == 1 {
                Placeholder(text: "No items found.", secondary: "Type in at least 2 characters to start the search.")
            } else if list.isEmpty && loaded {
                Placeholder(text: "No items found.")
            } else if !loaded {
                ProgressView().tint(palette.primaryColor).padding(32)
                Spacer()
            } else {
                ItemsList(items: list, grid: grid, highlight: q, actions: actions) { router.open($0.path) }
            }
        }
        .background(palette.backgroundColor.ignoresSafeArea())
        .itemActionSheets(actions)
        .task { load() }
        .onChange(of: list) { _, l in actions.items = l }
        .onChange(of: config.shouldShowHidden()) { _, _ in load() }
        .sheet(isPresented: $showSorting) { ChangeSortingDialog(path: key) }
        .sheet(isPresented: $showViewType) { ChangeViewTypeDialog(path: key, showFolderCheck: true) }
        .sheet(isPresented: $showColumnCount) {
            RadioDialog(title: nil, items: (1...maxColumnCount).map { ($0, "\($0) column\($0 == 1 ? "" : "s")") }, selected: config.fileColumnCnt) {
                config.fileColumnCnt = $0
            }
        }
    }

    private func load() {
        actions.refresh = { load() }
        let roots = storage.roots, hidden = config.shouldShowHidden(), category = category
        Task.detached {
            let items = FileOps.files(of: category, roots: roots, showHidden: hidden)
                .filter { hidden || !$0.path.isPathInHiddenFolder }
            await MainActor.run {
                stored = items
                loaded = true
            }
        }
    }

    private func toggleHidden() {
        if config.temporarilyShowHidden {
            config.temporarilyShowHidden = false
        } else {
            router.hiddenProtected { config.temporarilyShowHidden = true }
        }
    }
}
