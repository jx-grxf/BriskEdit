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

    /// The latest release's curated highlights. Update this for each release.
    static let sections: [Section] = [
        Section(name: "Performance", highlights: [
            Highlight(symbol: "bolt.fill", title: "Instant syntax highlighting", detail: "Tree-sitter highlighting for Swift and JSON with cached grammars — code files open immediately instead of stalling.", tint: .yellow),
            Highlight(symbol: "speedometer", title: "Performance modes", detail: "Low Power, Adaptive and Power — with background syntax indexing in Power mode so even the first open is instant.", tint: .green),
            Highlight(symbol: "doc.text.magnifyingglass", title: "Large-file aware", detail: "Heavy features ease off automatically above a few megabytes to keep editing smooth.", tint: .teal),
        ]),
        Section(name: "Source control", highlights: [
            Highlight(symbol: "text.alignleft", title: "Inline git blame", detail: "See who last changed the current line, right where your cursor is.", tint: .orange),
            Highlight(symbol: "circle.grid.2x2", title: "File-tree git badges", detail: "Modified, added and untracked files are marked in the sidebar at a glance.", tint: .blue),
        ]),
        Section(name: "Getting started", highlights: [
            Highlight(symbol: "sparkles", title: "Guided setup", detail: "A quick onboarding configures performance, theme and source control — replay it any time from Settings.", tint: .purple),
            Highlight(symbol: "terminal", title: "The briskedit command", detail: "Open files and folders with briskedit . — plus a shorter brisk alias when that name is available.", tint: .pink),
        ]),
    ]
}
