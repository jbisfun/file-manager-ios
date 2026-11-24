import FossifyCommons
import SwiftUI

/// SettingsActivity.
struct SettingsView: View {
    @Environment(Router.self) private var router
    @Environment(Config.self) private var config
    @Environment(\.palette) private var palette

    @State private var manageTabs = false
    @State private var dateTimeFormat = false
    @State private var fontSize = false

    var body: some View {
        @Bindable var config = config
        VStack(spacing: 0) {
            TopBar(title: "Settings")
            ScrollView {
                VStack(spacing: 0) {
                    Text("Color customization").sectionHeader(palette)
                    SettingsItem("Customize colors") { router.push(.customizeColors) }

                    Text("General").sectionHeader(palette)
                    SettingsItem("Manage favorites") { router.push(.favorites) }
                    SettingsItem("Manage shown tabs") { manageTabs = true }
                    SettingsItem("Change date and time format") { dateTimeFormat = true }
                    SettingsItem("Font size", value: BaseConfig.shared.fontSize.title) { fontSize = true }

                    Text("Visibility").sectionHeader(palette)
                    SettingsToggle("Show hidden items", isOn: Binding(get: { config.showHidden }, set: { on in
                        if on { router.hiddenProtected { config.showHidden = true } } else { config.showHidden = false }
                    }))

                    Text("Scrolling").sectionHeader(palette)
                    SettingsToggle("Enable pull-to-refresh from the top", isOn: $config.enablePullToRefresh)

                    Text("File operations").sectionHeader(palette)
                    SettingsToggle("Keep old last-modified value at file operations", isOn: $config.keepLastModified)
                    SettingsToggle("Always skip delete confirmation dialog", isOn: $config.skipDeleteConfirmation)

                    Text("Security").sectionHeader(palette)
                    StoredProtectionToggle("Password protect hidden item visibility", keys: .hiddenItems)
                    PasswordProtectionToggle("Password protect the whole application", kind: .app)
                    PasswordProtectionToggle("Password protect file deletion", kind: .delete)
                }
                .padding(.bottom, 32)
            }
        }
        .background(palette.backgroundColor.ignoresSafeArea())
        .sheet(isPresented: $manageTabs) { ManageVisibleTabsDialog() }
        .sheet(isPresented: $dateTimeFormat) { ChangeDateTimeFormatDialog() }
        .sheet(isPresented: $fontSize) {
            RadioDialog(title: nil, items: FontSize.allCases.map { ($0, $0.title) }, selected: BaseConfig.shared.fontSize) { BaseConfig.shared.fontSize = $0 }
        }
    }
}

extension AppInfo {
    public static let fileManager = AppInfo(name: "File Manager", icon: "folder.fill", upstream: "File-Manager", port: "file-manager-ios", policy: "file-manager",
                                            faq: [
                                                ("I deleted some files by mistake, how can I recover them?",
                                                 "Sadly, you cannot. Files are deleted instantly after the confirmation dialog, there is no trashbin available."),
                                                ("How can I select multiple items at once?",
                                                 "Start the selection mode by long pressing one item, then tap the others to select them."),
                                                ("Where are my files?",
                                                 "\"Internal\" is the app's own folder, also shown in the Files app under On My iPhone › File Manager. Tap the first part of the path to switch storages or add folders from other locations, like iCloud Drive."),
                                            ])
}
