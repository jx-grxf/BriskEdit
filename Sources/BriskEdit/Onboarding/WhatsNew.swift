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
    /// runs instead — and unchanged relaunches don't pop the page). Nightly builds
    /// never announce: every build is an update, and the curated highlights
    /// describe the last release rather than what changed on `dev`.
    static func versionToAnnounceAndMarkSeen(distribution: AppDistribution = .current) -> String? {
        guard distribution == .release else { return nil }
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
    static let highlightsVersion = "0.6.2"

    /// The latest release's curated highlights. **Update this for each release**
    /// (mirrors the top section of RELEASE_NOTES.md) — see the release recipe in
    /// the project notes so it doesn't get missed.
    static let sections: [Section] = [
        Section(name: "A clearer workspace", highlights: [
            Highlight(symbol: "text.alignleft", title: "Reliable editor rendering", detail: "Text and line numbers stay visible with the minimap enabled, including when editor vibrancy is off.", tint: .blue),
            Highlight(symbol: "folder", title: "Refreshed welcome screen", detail: "Find recent workspaces, file and folder actions, and project context more easily.", tint: .teal),
        ]),
        Section(name: "Updates", highlights: [
            Highlight(symbol: "arrow.triangle.2.circlepath", title: "Reliable beta updates", detail: "The beta update feed is published at the address installed clients check.", tint: .orange),
            Highlight(symbol: "moon.stars", title: "Clearer Nightly identity", detail: "The separate Nightly app has its own name, violet accent and window marker, with versions that show the release ahead.", tint: .purple),
        ]),
    ]
}
