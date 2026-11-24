import FossifyCommons
import SwiftUI

/// DecompressActivity: browse a zip file and extract it.
struct DecompressView: View {
    @Environment(Router.self) private var router
    @Environment(Config.self) private var config
    @Environment(Storage.self) private var storage
    @Environment(\.palette) private var palette
    let path: String
    @State private var entries: [Zip.EntryInfo] = []
    @State private var current = ""
    @State private var loading = true
    @State private var pickDestination = false

    var body: some View {
        let items = entries
            .filter { ($0.path.contains("/") ? $0.path.parentPath : "") == current }
            .sorted { $0.isDirectory != $1.isDirectory ? $0.isDirectory : $0.path.filenameFromPath < $1.path.filenameFromPath }
        VStack(spacing: 0) {
            TopBar(title: path.filenameFromPath, onBack: back, background: nil, tint: nil) {
                IconButton(icon: "arrow.up.bin") { pickDestination = true }
            }
            if loading {
                ProgressView().progressViewStyle(.linear).tint(palette.primaryColor)
            }
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(items, id: \.path) { entry in
                        HStack(spacing: 14) {
                            if entry.isDirectory {
                                Image(systemName: "folder.fill").resizable().scaledToFit().padding(4)
                                    .foregroundStyle(palette.primaryColor.opacity(0.7)).frame(width: 40, height: 40)
                            } else {
                                Image(systemName: fileTypeIcon(entry.path)).resizable().scaledToFit().padding(8)
                                    .foregroundStyle(palette.secondaryText).frame(width: 40, height: 40)
                            }
                            Text(entry.path.filenameFromPath).font(.system(size: palette.fontSize)).lineLimit(1)
                            Spacer()
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                        .contentShape(Rectangle())
                        .onTapGesture { if entry.isDirectory { current = entry.path } }
                    }
                }
            }
        }
        .background(palette.backgroundColor.ignoresSafeArea())
        .task { load() }
        .sheet(isPresented: $pickDestination) {
            FilePickerDialog(path: StorageRoot.containing(path, in: storage.roots) == nil ? config.homeFolder : path.parentPath, roots: storage.roots, showHidden: config.showHidden, showFAB: true,
                             canAddShowHiddenButton: true, favorites: config.favorites) { destination in
                decompress(to: destination)
            }
        }
    }

    private func back() {
        if current.isEmpty { router.pop() } else { current = current.contains("/") ? current.parentPath : "" }
    }

    private func load() {
        let path = path
        Task.detached {
            do {
                let list = try Zip.entries(path)
                await MainActor.run {
                    entries = list
                    loading = false
                }
            } catch Zip.Failure.encrypted {
                await MainActor.run {
                    router.toast = "Password-protected archives are not supported"
                    router.pop()
                }
            } catch {
                await MainActor.run {
                    router.toast = "An unknown error occurred"
                    loading = false
                }
            }
        }
    }

    /// decompressTo(): everything goes into <destination>/<archive name>.
    private func decompress(to destination: String) {
        let path = path
        let folder = "\(destination)/\(path.filenameFromPath.fileExtension.isEmpty ? path.filenameFromPath : String(path.filenameFromPath.dropLast(path.fileExtension.count + 1)))"
        Task.detached {
            let ok = (try? Zip.extract(path, into: folder)) != nil
            await MainActor.run {
                router.toast = ok ? "Decompression successful" : "Decompressing failed"
                if ok { router.pop() }
            }
        }
    }
}
