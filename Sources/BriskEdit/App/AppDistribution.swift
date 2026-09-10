import Foundation

/// Which build of BriskEdit is running. Stable and beta releases share one app
/// bundle; nightly builds from the `dev` branch are a separate app with their own
/// bundle identifier, icon and update feed, so they install next to a release.
/// The flavor is stamped into Info.plist at build time (`BRISKEDIT_DISTRIBUTION`).
enum AppDistribution: String, Sendable {
    case release
    case nightly

    static let current = AppDistribution(infoDictionary: Bundle.main.infoDictionary)

    init(infoDictionary: [String: Any]?) {
        let raw = infoDictionary?["BriskEditDistribution"] as? String
        self = raw.flatMap(AppDistribution.init(rawValue:)) ?? .release
    }

    var displayName: String {
        switch self {
        case .release: "BriskEdit"
        case .nightly: "BriskEdit Nightly"
        }
    }

    /// Application Support folder for state a side-by-side install must not
    /// share, such as draft recovery and the CLI launcher script.
    var supportDirectoryName: String { displayName }

    /// Shell command names installed by `CLIInstaller`. Nightly gets its own
    /// names so installing its launcher never retargets `brisk` away from a release.
    var cliCommandNames: (primary: String, alias: String) {
        switch self {
        case .release: ("briskedit", "brisk")
        case .nightly: ("briskedit-nightly", "brisk-nightly")
        }
    }

    /// Short commit the nightly was built from; empty for local and release builds.
    static var sourceCommit: String? {
        let commit = Bundle.main.infoDictionary?["BriskEditSourceCommit"] as? String
        return commit?.isEmpty == false ? commit : nil
    }
}
