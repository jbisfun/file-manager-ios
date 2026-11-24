import FossifyCommons
import SwiftUI

/// FavoritesActivity + ManageFavoritesAdapter.
struct FavoritesView: View {
    @Environment(Router.self) private var router
    @Environment(Config.self) private var config
    @Environment(Storage.self) private var storage
    @Environment(\.palette) private var palette
    @State private var selection = Set<String>()
    @State private var addFavorite = false

    var body: some View {
        let favorites = config.favorites
        VStack(spacing: 0) {
            if selection.isEmpty {
                TopBar(title: "Manage favorites", onBack: { router.pop() }, background: nil, tint: nil) {
                    IconButton(icon: "plus") { addFavorite = true }
                }
            } else {
                HStack(spacing: 0) {
                    IconButton(icon: "xmark") { selection.removeAll() }
                    Text("\(selection.count) / \(favorites.count)").font(.system(size: 20, weight: .medium)).padding(.leading, 4)
                    Spacer()
                    IconButton(icon: "minus.circle") {
                        for f in selection { config.removeFavorite(f) }
                        selection.removeAll()
                    }
                }
                .foregroundStyle(palette.onPrimary)
                .padding(.horizontal, 4)
                .frame(height: 64)
                .background(palette.primaryColor.ignoresSafeArea(edges: .top))
            }
            if favorites.isEmpty {
                Placeholder(text: "You can add frequently used folders to favorites for easy access from anywhere.", action: "Add favorites") {
                    addFavorite = true
                }
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(favorites, id: \.self) { favorite in
                            HStack {
                                Text(favorite).font(.system(size: palette.fontSize)).lineLimit(3)
                                Spacer()
                                Menu {
                                    Button(role: .destructive) { config.removeFavorite(favorite) } label: { Label("Remove", systemImage: "minus.circle") }
                                } label: {
                                    Image(systemName: "ellipsis").rotationEffect(.degrees(90)).frame(width: 44, height: 44)
                                }
                            }
                            .padding(.leading, 16)
                            .padding(.vertical, 6)
                            .background(selection.contains(favorite) ? palette.primaryColor.opacity(0.25) : Color.clear)
                            .contentShape(Rectangle())
                            .onTapGesture { if !selection.isEmpty { toggle(favorite) } }
                            .onLongPressGesture { toggle(favorite) }
                        }
                    }
                }
            }
        }
        .background(palette.backgroundColor.ignoresSafeArea())
        .sheet(isPresented: $addFavorite) {
            FilePickerDialog(path: config.homeFolder, roots: storage.roots, showHidden: config.shouldShowHidden(), canAddShowHiddenButton: true) {
                config.addFavorite($0)
            }
        }
    }

    private func toggle(_ f: String) {
        if selection.contains(f) { selection.remove(f) } else { selection.insert(f) }
    }
}
