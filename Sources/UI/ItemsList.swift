import FossifyCommons
import Observation
import SwiftUI
import UIKit

/// ItemsAdapter's selection and action mode (cab.xml) for one list.
@MainActor
@Observable
final class ItemActions {
    var selection: Set<String> = []
    var items: [ListItem] = []
    @ObservationIgnored var refresh: () -> Void = {}

    // Dialogs
    var renameOne: String?
    var renameMany: [String]?
    var properties: [String]?
    var openAs: String?
    var pickDestination: Bool? // true = copy, false = move
    var compress: [String]?
    var confirmDelete = false
    var conflict: ConflictCheck?
    var share: [URL]?

    var isActive: Bool { !selection.isEmpty }
    var selectable: [ListItem] { items.filter { !$0.isSectionTitle && !$0.isGridTypeDivider } }
    var selectedItems: [FileDirItem] { selectable.filter { selection.contains($0.path) }.map(\.item) }
    var selectedPaths: [String] { selectedItems.map(\.path) }

    func toggle(_ item: ListItem) {
        guard !item.isSectionTitle && !item.isGridTypeDivider else { return }
        if selection.contains(item.path) { selection.remove(item.path) } else { selection.insert(item.path) }
    }

    func finish() { selection.removeAll() }
}

/// The action mode bar replacing the search bar while items are selected.
struct SelectionBar: View {
    @Environment(\.palette) private var palette
    @Environment(Router.self) private var router
    @Environment(Config.self) private var config
    let actions: ItemActions

    var body: some View {
        let selected = actions.selectedItems
        let one = selected.count == 1
        let oneFile = one && !selected[0].isDirectory
        let hasUnhidden = selected.contains { !$0.name.hasPrefix(".") }
        let hasHidden = selected.contains { $0.name.hasPrefix(".") }
        HStack(spacing: 0) {
            IconButton(icon: "xmark") { actions.finish() }
            Text("\(selected.count) / \(actions.selectable.count)")
                .font(.system(size: 20, weight: .medium))
                .lineLimit(1)
                .padding(.leading, 4)
            Spacer()
            IconButton(icon: "trash") { delete() }
            IconButton(icon: "info.circle") { actions.properties = actions.selectedPaths }
            IconButton(icon: "pencil") { rename() }
            IconButton(icon: "square.and.arrow.up") {
                actions.share = FileOps.shareURLs(actions.selectedPaths, showHidden: config.shouldShowHidden())
            }
            Menu {
                if hasUnhidden {
                    Button { toggleVisibility(hide: true) } label: { Label("Hide", systemImage: "eye.slash") }
                }
                if hasHidden {
                    Button { toggleVisibility(hide: false) } label: { Label("Unhide", systemImage: "eye") }
                }
                Button { actions.selection = Set(actions.selectable.map(\.path)) } label: { Label("Select all", systemImage: "checklist") }
                if one {
                    Button {
                        router.toast = Launcher.copy(selected[0].path)
                        actions.finish()
                    } label: { Label("Copy path to clipboard", systemImage: "doc.on.clipboard") }
                }
                if oneFile {
                    Button { router.open(selected[0].path, as: .other) } label: { Label("Open with", systemImage: "arrow.up.forward.app") }
                    Button { actions.openAs = selected[0].path } label: { Label("Open as", systemImage: "doc.viewfinder") }
                }
                Button { actions.pickDestination = true } label: { Label("Copy to", systemImage: "doc.on.doc") }
                Button { move() } label: { Label("Move to", systemImage: "folder") }
                Button { actions.compress = actions.selectedPaths } label: { Label("Compress", systemImage: "archivebox") }
                if selected.contains(where: { $0.path.isZipFile }) {
                    Button { decompress() } label: { Label("Decompress", systemImage: "arrow.up.bin") }
                }
            } label: {
                Image(systemName: "ellipsis").rotationEffect(.degrees(90)).font(.system(size: 18)).frame(width: 44, height: 48)
            }
        }
        .foregroundStyle(palette.onPrimary)
        .padding(.horizontal, 4)
        .frame(height: 64)
        .background(palette.primaryColor.ignoresSafeArea(edges: .top))
    }

    private func rename() {
        let selected = actions.selectedItems
        if selected.count == 1 {
            actions.renameOne = selected[0].path
        } else {
            actions.renameMany = selected.map(\.path)
        }
    }

    private func delete() {
        router.deleteProtected {
            if config.skipDeleteConfirmation { performDelete(actions, config: config, router: router) } else { actions.confirmDelete = true }
        }
    }

    private func move() {
        router.deleteProtected { actions.pickDestination = false }
    }

    private func toggleVisibility(hide: Bool) {
        let paths = actions.selectedPaths
        Task.detached {
            for p in paths { FileOps.toggleVisibility(p, hide: hide) }
            await MainActor.run {
                actions.refresh()
                actions.finish()
            }
        }
    }

    private func decompress() {
        let zips = actions.selectedPaths.filter(\.isZipFile)
        decompressNext(zips, ok: true)
    }

    /// tryDecompressingPaths(): one archive at a time, each into a folder named after it.
    private func decompressNext(_ zips: [String], ok: Bool) {
        guard let zip = zips.first else {
            router.toast = ok ? "Decompression successful" : "Decompressing failed"
            actions.refresh()
            if ok { actions.finish() }
            return
        }
        let name = zip.filenameFromPath
        let folder = "\(zip.parentPath)/\(String(name.dropLast(4)))"
        actions.conflict = ConflictCheck(items: Zip.topLevelItems(zip, folder: folder), destination: folder) { resolutions in
            Task.detached {
                let success = (try? Zip.extract(zip, into: folder, resolutions: resolutions)) != nil
                await MainActor.run { decompressNext(Array(zips.dropFirst()), ok: ok && success) }
            }
        }
    }
}

@MainActor
func performDelete(_ actions: ItemActions, config: Config, router: Router) {
    let paths = actions.selectedPaths
    for p in paths { config.removeFavorite(p) }
    actions.finish()
    Task.detached {
        let ok = FileOps.delete(paths)
        await MainActor.run {
            if !ok { router.toast = "An unknown error occurred" }
            actions.refresh()
        }
    }
}

/// Dialogs shared by every screen showing an ItemsAdapter.
struct ItemActionSheets: ViewModifier {
    @Environment(Router.self) private var router
    @Environment(Config.self) private var config
    @Environment(Storage.self) private var storage
    @Bindable var actions: ItemActions

    func body(content: Content) -> some View {
        content
            .sheet(item: Binding(get: { actions.renameOne.map(IdentifiedPath.init) }, set: { actions.renameOne = $0?.path })) { item in
                RenameItemDialog(path: item.path) { newPath in
                    config.moveFavorite(item.path, newPath)
                    actions.refresh()
                    actions.finish()
                }
            }
            .sheet(item: Binding(get: { actions.renameMany.map(IdentifiedPaths.init) }, set: { actions.renameMany = $0?.paths })) { item in
                RenameItemsDialog(paths: item.paths, allowPattern: !actions.selectedItems.contains(where: \.isDirectory)) {
                    actions.refresh()
                    actions.finish()
                }
            }
            .sheet(item: Binding(get: { actions.properties.map(IdentifiedPaths.init) }, set: { actions.properties = $0?.paths })) { item in
                PropertiesDialog(paths: item.paths, countHidden: config.shouldShowHidden(), humanize: storage.humanize)
            }
            .sheet(item: Binding(get: { actions.openAs.map(IdentifiedPath.init) }, set: { actions.openAs = $0?.path })) { item in
                RadioDialog(title: "Open as", items: [(OpenAs.text, "Text file"), (OpenAs.image, "Image file"), (OpenAs.audio, "Audio file"),
                                                      (OpenAs.video, "Video file"), (OpenAs.other, "Other file")],
                            selected: OpenAs.default) { type in
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { router.open(item.path, as: type) }
                }
            }
            .sheet(isPresented: Binding(get: { actions.pickDestination != nil }, set: { if !$0 { actions.pickDestination = nil } })) {
                let isCopy = actions.pickDestination ?? true
                let items = actions.selectedItems
                let source = items.first?.parentPath ?? Storage.internalPath
                var isDir: ObjCBool = false
                let last = config.lastCopyPath
                let start = !last.isEmpty && FileManager.default.fileExists(atPath: last, isDirectory: &isDir) && isDir.boolValue && last != source ? last : source
                FilePickerDialog(path: start, roots: storage.roots, showHidden: config.shouldShowHidden(), showFAB: true,
                                 canAddShowHiddenButton: true, favorites: config.favorites) { destination in
                    config.lastCopyPath = destination
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { copyMove(items, to: destination, copy: isCopy) }
                }
            }
            .sheet(item: Binding(get: { actions.compress.map(IdentifiedPaths.init) }, set: { actions.compress = $0?.paths })) { item in
                CompressAsDialog(path: item.paths[0]) { destination in
                    router.toast = "Compressing…"
                    Task.detached {
                        let ok = Zip.compress(item.paths, to: destination)
                        await MainActor.run {
                            router.toast = ok ? "Compression successful" : "Compressing failed"
                            if ok {
                                actions.refresh()
                                actions.finish()
                            }
                        }
                    }
                }
            }
            .sheet(item: Binding(get: { actions.share.map(URLList.init) }, set: { actions.share = $0?.urls })) { item in
                ShareSheet(items: item.urls)
            }
            .conflictCheck($actions.conflict)
            .alert(deleteQuestion, isPresented: $actions.confirmDelete) {
                Button("No", role: .cancel) {}
                Button("Yes", role: .destructive) { performDelete(actions, config: config, router: router) }
            }
    }

    private var deleteQuestion: String {
        let selected = actions.selectedItems
        let items = selected.count == 1 ? "\"\(selected[0].name)\"" : "\(selected.count) items"
        return "Are you sure you want to delete \(items)?"
    }

    /// copyMoveTo() + CopyMoveTask.
    private func copyMove(_ items: [FileDirItem], to destination: String, copy: Bool) {
        if items.contains(where: { destination == $0.path || destination.hasPrefix($0.path + "/") }) {
            router.toast = copy ? "Could not copy the files" : "Could not move the files"
            return
        }
        actions.conflict = ConflictCheck(items: items, destination: destination) { resolutions in
            router.toast = copy ? "Copying…" : "Moving…"
            let keep = config.keepLastModified, hidden = config.shouldShowHidden()
            Task.detached {
                let done = FileOps.copyMove(items, to: destination, copy: copy, resolutions: resolutions, keepLastModified: keep, copyHidden: hidden)
                await MainActor.run {
                    if copy {
                        router.toast = done == items.count ? "Files copied successfully" : (done == 0 ? "Could not copy the files" : "Some files could not be copied")
                    } else {
                        for item in items where !FileManager.default.fileExists(atPath: item.path) {
                            config.moveFavorite(item.path, "\(destination)/\(item.name)")
                        }
                        router.toast = done == items.count ? "Files moved successfully" : (done == 0 ? "Could not move the files" : "Some files could not be moved")
                    }
                    actions.refresh()
                    actions.finish()
                }
            }
        }
    }
}

struct IdentifiedPath: Identifiable {
    let path: String
    var id: String { path }
}

struct IdentifiedPaths: Identifiable {
    let paths: [String]
    var id: String { paths.joined(separator: "|") }
}

extension View {
    func itemActionSheets(_ actions: ItemActions) -> some View { modifier(ItemActionSheets(actions: actions)) }
}

/// The RecyclerView of ItemsAdapter: list or grid of items, with selection and pinch-to-zoom.
struct ItemsList: View {
    @Environment(\.palette) private var palette
    @Environment(Config.self) private var config
    let items: [ListItem]
    let grid: Bool
    var highlight = ""
    let actions: ItemActions
    var refreshable = false
    var onRefresh: () async -> Void = {}
    let onClick: (ListItem) -> Void

    var body: some View {
        let scroll = ScrollView {
            content.padding(.bottom, 96)
        }
        .simultaneousGesture(MagnifyGesture().onEnded { value in
            guard grid else { return }
            if value.magnification > 1.25, config.fileColumnCnt > 1 {
                config.fileColumnCnt -= 1
                actions.finish()
            } else if value.magnification < 0.8, config.fileColumnCnt < maxColumnCount {
                config.fileColumnCnt += 1
                actions.finish()
            }
        })
        if refreshable && !actions.isActive {
            scroll.refreshable { await onRefresh() }
        } else {
            scroll
        }
    }

    @ViewBuilder
    private var content: some View {
        if grid {
            VStack(spacing: 0) {
                ForEach(segments, id: \.0) { _, segment in
                    if segment.count == 1, segment[0].isSectionTitle || segment[0].isGridTypeDivider {
                        if segment[0].isSectionTitle { SectionRow(item: segment[0], highlight: highlight).onTapGesture { onClick(segment[0]) } } else { Color.clear.frame(height: 16) }
                    } else {
                        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 2), count: max(1, config.fileColumnCnt)), spacing: 2) {
                            ForEach(segment) { item in cell(item) }
                        }
                        .padding(.horizontal, 4)
                    }
                }
            }
        } else {
            LazyVStack(spacing: 0) {
                ForEach(items) { item in
                    if item.isSectionTitle {
                        SectionRow(item: item, highlight: highlight).onTapGesture { onClick(item) }
                    } else if !item.isGridTypeDivider {
                        row(item)
                    }
                }
            }
        }
    }

    /// Runs of grid cells, split by full-width section titles and dividers.
    private var segments: [(Int, [ListItem])] {
        var result: [(Int, [ListItem])] = []
        var current: [ListItem] = []
        for item in items {
            if item.isSectionTitle || item.isGridTypeDivider {
                if !current.isEmpty { result.append((result.count, current)) }
                current = []
                result.append((result.count, [item]))
            } else {
                current.append(item)
            }
        }
        if !current.isEmpty { result.append((result.count, current)) }
        return result
    }

    private func tap(_ item: ListItem) {
        if actions.isActive { actions.toggle(item) } else { onClick(item) }
    }

    private func longPress(_ item: ListItem) {
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        actions.toggle(item)
    }

    private func row(_ item: ListItem) -> some View {
        let selected = actions.selection.contains(item.path)
        let size = palette.fontSize
        return HStack(spacing: 14) {
            ItemIcon(item: item.item, size: 44)
            VStack(alignment: .leading, spacing: 2) {
                Text(highlighted(item.name, highlight, color: palette.primaryColor))
                    .font(.system(size: size))
                    .lineLimit(1)
                    .truncationMode(.middle)
                HStack {
                    Text(item.isDirectory ? item.item.children.itemsText : item.item.size.formattedSize)
                        .font(.system(size: size * 0.8))
                    Spacer()
                    if !item.isDirectory {
                        Text(DateTimeFormat.shared.format(item.item.modified))
                            .font(.system(size: size * 0.8))
                    }
                }
                .foregroundStyle(palette.secondaryText)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(selected ? palette.primaryColor.opacity(0.25) : Color.clear)
        .contentShape(Rectangle())
        .onTapGesture { tap(item) }
        .onLongPressGesture { longPress(item) }
    }

    private func cell(_ item: ListItem) -> some View {
        let selected = actions.selection.contains(item.path)
        return GeometryReader { geo in
            VStack(spacing: 2) {
                ItemIcon(item: item.item, size: max(16, geo.size.width - (item.isDirectory || config.displayFilenames ? 24 : 8)))
                if item.isDirectory || config.displayFilenames {
                    Text(highlighted(item.name, highlight, color: palette.primaryColor))
                        .font(.system(size: palette.fontSize * 0.8))
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }
            .frame(width: geo.size.width, height: geo.size.height)
        }
        .aspectRatio(1, contentMode: .fit)
        .padding(2)
        .background(selected ? palette.primaryColor.opacity(0.25) : Color.clear)
        .overlay(alignment: .topTrailing) {
            if selected {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 20))
                    .foregroundStyle(palette.onPrimary, palette.primaryColor)
                    .padding(4)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture { tap(item) }
        .onLongPressGesture { longPress(item) }
    }
}

/// item_section: a folder of the search results.
struct SectionRow: View {
    @Environment(\.palette) private var palette
    let item: ListItem
    let highlight: String

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "folder.fill").foregroundStyle(palette.primaryColor.opacity(0.7))
            Text(highlighted(item.name, highlight, color: palette.primaryColor))
                .font(.system(size: palette.fontSize))
                .lineLimit(2)
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .contentShape(Rectangle())
    }
}
