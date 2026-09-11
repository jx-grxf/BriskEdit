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
    static let highlightsVersion = "0.6.1"

    /// The latest release's curated highlights. **Update this for each release**
    /// (mirrors the top section of RELEASE_NOTES.md) — see the release recipe in
    /// the project notes so it doesn't get missed.
    static let sections: [Section] = [
        Section(name: "A fresh look", highlights: [
            Highlight(symbol: "chevron.left.forwardslash.chevron.right", title: "New app icon", detail: "A redesigned icon with code brackets and a pencil. On macOS 26 it uses Liquid Glass and follows the Dark, Tinted, and Clear icon styles.", tint: .blue),
            Highlight(symbol: "info.circle", title: "Clearer version display", detail: "Settings and the About window show the version, for example 0.6.1, instead of an internal build number.", tint: .teal),
        ]),
    ]
}
