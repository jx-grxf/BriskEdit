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
    static let highlightsVersion = "0.6.0"

    /// The latest release's curated highlights. **Update this for each release**
    /// (mirrors the top section of RELEASE_NOTES.md) — see the release recipe in
    /// the project notes so it doesn't get missed.
    static let sections: [Section] = [
        Section(name: "Your work, protected", highlights: [
            Highlight(symbol: "xmark.rectangle", title: "Reliable tab closing", detail: "Close a tab without accidentally selecting it again or starting a drag. Move tabs by dragging their labels; the close button stays independent.", tint: .blue),
            Highlight(symbol: "arrow.counterclockwise.circle", title: "Recover unsaved drafts", detail: "Restore local recovery copies after an unexpected exit, including untitled files. Recovered drafts open as copies so existing files stay safe.", tint: .teal),
            Highlight(symbol: "doc.on.doc", title: "Compare before overwriting", detail: "Inspect the editor buffer against the saved file. Autosave pauses when an external change needs your decision.", tint: .blue),
        ]),
        Section(name: "Navigate and review", highlights: [
            Highlight(symbol: "text.magnifyingglass", title: "Find references", detail: "See where a symbol is used with your language server, then open a result at its exact location.", tint: .indigo),
            Highlight(symbol: "arrow.triangle.branch", title: "Review Git changes", detail: "Read staged and unstaged diffs from Source Control. Navigate open tabs with Shift–Command–[ and ].", tint: .orange),
        ]),
        Section(name: "A calmer Mac experience", highlights: [
            Highlight(symbol: "macwindow", title: "Frosted editor backgrounds", detail: "Choose Subtle, Balanced, or Strong vibrancy in Appearance while keeping your syntax theme. Reduce Transparency and Low Power switch to a solid background.", tint: .cyan),
            Highlight(symbol: "macwindow", title: "More Macs, native materials", detail: "Now supports macOS 15 and later, with Liquid Glass on macOS 26 and native material fallbacks on earlier systems.", tint: .blue),
            Highlight(symbol: "bolt", title: "Smoother editing", detail: "Folding analysis runs away from the UI. Cancelled searches stop their work, and window sizing respects your adjustments.", tint: .teal),
        ]),
    ]
}
