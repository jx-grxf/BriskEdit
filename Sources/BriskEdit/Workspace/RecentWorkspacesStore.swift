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
        folders = (UserDefaults.standard.stringArray(forKey: Self.key) ?? [])
            .map { URL(fileURLWithPath: $0) }
    }

    func record(_ url: URL) {
        let path = url.standardizedFileURL.path
        var paths = folders.map(\.path)
        paths.removeAll { $0 == path }
        paths.insert(path, at: 0)
        if paths.count > Self.limit { paths = Array(paths.prefix(Self.limit)) }
        folders = paths.map { URL(fileURLWithPath: $0) }
        UserDefaults.standard.set(paths, forKey: Self.key)
    }

    func clear() {
        folders = []
        UserDefaults.standard.removeObject(forKey: Self.key)
    }
}
