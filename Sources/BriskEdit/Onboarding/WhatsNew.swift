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
    static let highlightsVersion = "0.5.1"

    /// The latest release's curated highlights. **Update this for each release**
    /// (mirrors the top section of RELEASE_NOTES.md) — see the release recipe in
    /// the project notes so it doesn't get missed.
    static let sections: [Section] = [
        Section(name: "Source control", highlights: [
            Highlight(symbol: "point.3.connected.trianglepath.dotted", title: "Commit history with a graph", detail: "The Source Control pane lists recent commits with a graph lane and marks the ones you haven't pushed yet.", tint: .blue),
            Highlight(symbol: "arrow.clockwise", title: "Always up to date", detail: "Opening the pane, returning to the window, or saving a file refreshes the status and diffs right away — no manual refresh.", tint: .green),
        ]),
        Section(name: "Languages", highlights: [
            Highlight(symbol: "cup.and.saucer.fill", title: "Run and IntelliSense for Java", detail: "Run Java files straight from the editor and get completion, diagnostics and hovers when a Java language server is installed.", tint: .orange),
        ]),
        Section(name: "Markdown", highlights: [
            Highlight(symbol: "doc.richtext", title: "Sharper Markdown preview", detail: "Ordered and task lists, horizontal rules, more heading levels, italics and strikethrough, with a cleaner GitHub-style look in light and dark.", tint: .purple),
        ]),
        Section(name: "Stability", highlights: [
            Highlight(symbol: "checkmark.shield", title: "Folder drops undo safely", detail: "Dropping a folder to swap the workspace root no longer leaves stale editor undo state behind.", tint: .teal),
        ]),
    ]
}
