import Foundation
import Observation

/// App-wide list of recently opened workspace folders, persisted in defaults and
/// surfaced as File ▸ Open Recent. Observable so the menu refreshes live.
@MainActor
@Observable
final class RecentWorkspacesStore {
    static let shared = RecentWorkspacesStore()

    private static let key = "workspace.recentFolders"
    private static let filesKey = "workspace.recentFiles"
    private static let limit = 10

    private(set) var folders: [URL]
    /// Recently opened files (as opposed to folders), surfaced as the top section
    /// of File ▸ Open Recent.
    private(set) var files: [URL]

    private init() {
        let stored = (UserDefaults.standard.stringArray(forKey: Self.key) ?? [])
            .map { URL(fileURLWithPath: $0) }
        // Drop folders living in a temporary directory (test fixtures, scratch
        // space): they're deleted out from under us and would otherwise linger
        // forever as greyed-out, un-openable entries.
        let storedFiles = (UserDefaults.standard.stringArray(forKey: Self.filesKey) ?? [])
            .map { URL(fileURLWithPath: $0) }
        folders = stored.filter { Self.isEligible($0) }
        files = storedFiles.filter { Self.isEligible($0) }
        if folders.count != stored.count { persist() }
        if files.count != storedFiles.count { persistFiles() }
    }

    func record(_ url: URL) {
        folders = Self.upsert(url, into: folders)
        persist()
    }

    func recordFile(_ url: URL) {
        files = Self.upsert(url, into: files)
        persistFiles()
    }

    func clear() {
        folders = []
        files = []
        UserDefaults.standard.removeObject(forKey: Self.key)
        UserDefaults.standard.removeObject(forKey: Self.filesKey)
    }

    private func persist() {
        UserDefaults.standard.set(folders.map(\.path), forKey: Self.key)
    }

    private func persistFiles() {
        UserDefaults.standard.set(files.map(\.path), forKey: Self.filesKey)
    }

    /// Moves `url` to the front of the list, deduplicating by standardized path
    /// and capping the length.
    private static func upsert(_ url: URL, into existing: [URL]) -> [URL] {
        guard isEligible(url) else { return existing }
        let path = url.standardizedFileURL.path
        var paths = existing.map(\.path)
        paths.removeAll { $0 == path }
        paths.insert(path, at: 0)
        if paths.count > limit { paths = Array(paths.prefix(limit)) }
        return paths.map { URL(fileURLWithPath: $0) }
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

/// App-wide bounded stack of recently closed file tabs, backing File ▸ Reopen
/// Closed Tab (⇧⌘T). Global rather than per-window so a tab closed in any
/// window can be reopened into the one the user is currently working in. Not
/// persisted: a closed tab is a transient undo, unlike recents.
@MainActor
@Observable
final class ClosedTabHistory {
    static let shared = ClosedTabHistory()

    private static let limit = 20

    private(set) var urls: [URL] = []

    /// Only file-backed tabs are recorded; untitled and What's New tabs have no
    /// URL to come back to. Preview tabs are recorded — reopening routes through
    /// `openFile`, which restores them as previews.
    func record(_ url: URL) {
        guard RecentWorkspacesStore.isEligible(url) else { return }
        let path = url.standardizedFileURL.path
        urls.removeAll { $0.path == path }
        urls.insert(URL(fileURLWithPath: path), at: 0)
        if urls.count > Self.limit { urls = Array(urls.prefix(Self.limit)) }
    }

    func pop() -> URL? {
        guard !urls.isEmpty else { return nil }
        return urls.removeFirst()
    }

    func clear() {
        urls = []
    }
}
