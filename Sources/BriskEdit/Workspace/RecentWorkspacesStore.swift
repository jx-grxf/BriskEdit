import Foundation
import Observation

/// App-wide list of recently opened workspace folders, persisted in defaults and
/// surfaced as File ▸ Open Recent. Observable so the menu refreshes live.
@MainActor
@Observable
final class RecentWorkspacesStore {
    static let shared = RecentWorkspacesStore()

    private static let key = "workspace.recentFolders"
    private static let limit = 10

    private(set) var folders: [URL]

    private init() {
        let stored = (UserDefaults.standard.stringArray(forKey: Self.key) ?? [])
            .map { URL(fileURLWithPath: $0) }
        // Drop folders living in a temporary directory (test fixtures, scratch
        // space): they're deleted out from under us and would otherwise linger
        // forever as greyed-out, un-openable entries.
        folders = stored.filter { Self.isEligible($0) }
        if folders.count != stored.count { persist() }
    }

    func record(_ url: URL) {
        guard Self.isEligible(url) else { return }
        let path = url.standardizedFileURL.path
        var paths = folders.map(\.path)
        paths.removeAll { $0 == path }
        paths.insert(path, at: 0)
        if paths.count > Self.limit { paths = Array(paths.prefix(Self.limit)) }
        folders = paths.map { URL(fileURLWithPath: $0) }
        persist()
    }

    func clear() {
        folders = []
        UserDefaults.standard.removeObject(forKey: Self.key)
    }

    private func persist() {
        UserDefaults.standard.set(folders.map(\.path), forKey: Self.key)
    }

    /// A folder is worth remembering only if it isn't inside a temporary
    /// directory. Real folders the user later deletes stay in the list and are
    /// shown greyed-out (matching the system "Open Recent" idiom); only throwaway
    /// temp paths are filtered, since they never come back.
    static func isEligible(_ url: URL) -> Bool {
        let path = url.standardizedFileURL.path
        let tmp = URL(fileURLWithPath: NSTemporaryDirectory()).standardizedFileURL.path
        return !(path == tmp
            || path.hasPrefix(tmp + "/")
            || path.hasPrefix("/var/folders/")
            || path.hasPrefix("/private/var/folders/")
            || path.hasPrefix("/tmp/")
            || path.hasPrefix("/private/tmp/"))
    }
}
