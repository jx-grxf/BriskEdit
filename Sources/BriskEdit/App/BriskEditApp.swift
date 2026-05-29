import SwiftUI

@main
struct BriskEditApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var preferences = Preferences()
    @State private var updates = UpdateService()

    var body: some Scene {
        WindowGroup(id: "workspace") {
            WorkspaceWindow()
                .environment(preferences)
                .environment(updates)
                .frame(minWidth: 900, minHeight: 560)
        }
        .windowStyle(.titleBar)
        .windowToolbarStyle(.unified(showsTitle: true))
        .commands {
            AppCommands(updates: updates)
        }

        Settings {
            SettingsScene()
                .environment(preferences)
                .environment(updates)
        }
    }
}
