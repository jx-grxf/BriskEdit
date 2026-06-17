import Foundation
import SwiftUI

/// Curated "What's New" content and the logic that decides when to surface it.
enum WhatsNew {
    static var currentVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? ""
    }

    private static let lastSeenVersionKey = "app.lastSeenVersion"

    /// Records the running version and returns it **only** when the app was
    /// updated since the previous launch (so the first install — where onboarding
    /// runs instead — and unchanged relaunches don't pop the page).
    static func versionToAnnounceAndMarkSeen() -> String? {
        let current = currentVersion
        guard !current.isEmpty else { return nil }
        let defaults = UserDefaults.standard
        let previous = defaults.string(forKey: lastSeenVersionKey)
        defaults.set(current, forKey: lastSeenVersionKey)
        guard let previous, previous != current else { return nil }
        return current
    }

    struct Highlight: Identifiable {
        let id = UUID()
        let symbol: String
        let title: String
        let detail: String
        var tint: Color = .accentColor
    }

    struct Section: Identifiable {
        let id = UUID()
        let name: String
        let highlights: [Highlight]
    }

    /// The headline subtitle shown under the version.
    static let tagline = "A native macOS editor that opens instantly and uses the tools already on your Mac."

    /// The release whose highlights `sections` describe. Must equal
    /// `MARKETING_VERSION`; `script/verify_release_metadata.sh` enforces it in CI
    /// so the in-app What's New page can't silently ship the previous release's
    /// highlights. Bump this together with `sections` (and the release notes).
    static let highlightsVersion = "0.5.0"

    /// The latest release's curated highlights. **Update this for each release**
    /// (mirrors the top section of RELEASE_NOTES.md) — see the release recipe in
    /// the project notes so it doesn't get missed.
    static let sections: [Section] = [
        Section(name: "Tabs", highlights: [
            Highlight(symbol: "arrow.left.and.right", title: "Rearrange tabs by dragging", detail: "Drag tabs to reorder them, with a smooth spring and a clear drop indicator.", tint: .blue),
            Highlight(symbol: "macwindow.on.rectangle", title: "Tear off and move tabs", detail: "Drag a tab onto the desktop to open it in a new window, or onto another window to move it there — unsaved edits and the language server come along.", tint: .teal),
            Highlight(symbol: "keyboard", title: "Keyboard and overflow controls", detail: "Move the active tab with ⌃⌘← / ⌃⌘→, and jump to any tab from the overflow menu when the strip is full.", tint: .indigo),
        ]),
        Section(name: "Setup", highlights: [
            Highlight(symbol: "wrench.and.screwdriver.fill", title: "Set up your toolchains", detail: "Onboarding detects the compilers, language servers and formatters on your Mac and installs the missing ones with one click.", tint: .green),
            Highlight(symbol: "arrow.triangle.branch", title: "Optional source control", detail: "Turn the whole Source Control UI on or off with a single switch — for when you're not working in a repository.", tint: .orange),
        ]),
        Section(name: "Polish", highlights: [
            Highlight(symbol: "info.circle", title: "About page", detail: "Version, license and project links, now in Settings.", tint: .purple),
            Highlight(symbol: "clock.arrow.circlepath", title: "Tidier Recent folders", detail: "The welcome screen's Recent list no longer keeps temporary or deleted directories.", tint: .pink),
        ]),
    ]
}
