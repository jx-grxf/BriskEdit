import SwiftUI

@main
struct BriskEditApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var preferences = Preferences()
    @State private var updates = UpdateService()

    var body: some Scene {
        WindowGroup(for: WindowKind.self) { $kind in
            WorkspaceWindow(kind: kind)
                .environment(preferences)
                .environment(updates)
                .environment(ThemeStore.shared)
                .frame(minWidth: 900, minHeight: 560)
        } defaultValue: {
            .primary
        }
        .windowStyle(.titleBar)
        .windowToolbarStyle(.unified(showsTitle: true))
        .commands {
            AppCommands(updates: updates, preferences: preferences)
        }

        Settings {
            SettingsScene()
                .environment(preferences)
                .environment(updates)
                .environment(ThemeStore.shared)
        }
    }
}
