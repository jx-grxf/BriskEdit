import AppKit
import SwiftUI

@main
struct BriskEditApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var preferences = Preferences()
    @State private var updates = UpdateService()

    /// Full visible frame of the main display at launch. Used as the window's
    /// `defaultSize` so SwiftUI's *own* sizing pass targets full-size — the
    /// AppKit `setFrame` enforcement alone lost a race against this pass and the
    /// window kept opening small.
    private static let defaultWindowSize: CGSize = {
        let visible = (NSScreen.main ?? NSScreen.screens.first)?.visibleFrame.size
        return CGSize(width: visible?.width ?? 1440, height: visible?.height ?? 900)
    }()

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
        .defaultSize(width: Self.defaultWindowSize.width, height: Self.defaultWindowSize.height)
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
