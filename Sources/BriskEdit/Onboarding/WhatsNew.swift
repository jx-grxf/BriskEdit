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
    static let highlightsVersion = "0.5.2"

    /// The latest release's curated highlights. **Update this for each release**
    /// (mirrors the top section of RELEASE_NOTES.md) — see the release recipe in
    /// the project notes so it doesn't get missed.
    static let sections: [Section] = [
        Section(name: "Trusted by macOS", highlights: [
            Highlight(symbol: "checkmark.seal.fill", title: "Signed and notarized", detail: "BriskEdit is now signed with a Developer ID and notarized by Apple — the app opens like any other Mac app, no Gatekeeper workaround needed.", tint: .green),
        ]),
        Section(name: "Editor", highlights: [
            Highlight(symbol: "curlybraces", title: "Surround with brackets or quotes", detail: "Select text and type a bracket or quote to wrap it instead of replacing it, with the selection kept so you can keep typing.", tint: .blue),
            Highlight(symbol: "delete.left", title: "Smarter pairing", detail: "Typing a closer steps over the existing one, backspace inside an empty pair removes both, and quotes no longer auto-close inside words like don't.", tint: .purple),
        ]),
        Section(name: "Stability", highlights: [
            Highlight(symbol: "internaldrive", title: "Rapid saves can't lose edits", detail: "A save landing while an autosave was still writing could leave older content on disk — writes are now strictly ordered.", tint: .teal),
            Highlight(symbol: "xmark.rectangle", title: "Closing tabs respects Cancel", detail: "Close All and Close Other Tabs prompt for each unsaved file in order and stop the moment you cancel.", tint: .orange),
        ]),
    ]
}
