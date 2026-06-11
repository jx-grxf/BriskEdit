import AppKit
import Foundation
import Observation

/// Per-window editor state: open tabs, the active tab, the workspace root and
/// all the panes hanging off them. The class holds the stored state; its
/// behaviour is split across focused `WorkspaceModel+*.swift` extensions
/// (tabs, search, file tree, run, terminal, watching, file operations).
@MainActor
@Observable
final class WorkspaceModel {
    var rootURL: URL?
    var tabs: [EditorTab] = []
    var activeTabID: EditorTab.ID?
    var showCommandPalette: Bool = false
    var showFileFinder: Bool = false
    var showToolHealth: Bool = false
    var showTerminal: Bool = true
    var showMarkdownPreview: Bool = true
    var showHiddenFiles: Bool = false
    var reloadToken = UUID()
    /// Per-directory reload tokens. Bumping one reloads just that folder's branch
    /// in the file tree instead of the whole tree — so creating/deleting/renaming
    /// a file no longer scrolls the tree back to the top. Full refreshes (hidden
    /// toggle, manual Refresh, root change) still go through `reloadToken`.
    var directoryRefreshTokens: [URL: UUID] = [:]
    var selectedSidebarURL: URL?
    var lastError: String?
    /// Which sidebar pane is shown (files / search / source control). Lives here
    /// so menu commands can switch to it (e.g. Find in Files focuses search).
    var sidebarTab: SidebarTab = .files

    // MARK: - Project search (Find in Files)
    var searchQuery = SearchQuery(text: "")
    var searchReplacement = ""
    var searchResults: [SearchFileResult] = []
    var searchError: String?
    var searchReachedLimit = false
    var isSearching = false
    /// Bumped to ask the search sidebar to focus its input field.
    var focusSearchToken = 0
    var searchTask: Task<Void, Never>?

    // MARK: - Symbol outline
    var outlineSymbols: [LSPSymbol] = []
    var isLoadingOutline = false
    var outlineTask: Task<Void, Never>?
    /// Directories the user has expanded in the file tree — kept here (not in
    /// per-row @State) so the tree survives reloads without collapsing.
    var expandedDirectories: Set<URL> = []
    /// When set, a native or Markdown preview is shown beside the active editor.
    var splitPreviewContent: SplitPreviewContent?
    /// Open terminal sessions (VS Code-style). Each stays alive while the panel
    /// is shown; the list lets the user add, switch and close them.
    var terminals: [TerminalController] = []
    var activeTerminalID: TerminalController.ID?
    /// Only the primary window persists its folder + open tabs to the shared
    /// defaults; secondary windows are ephemeral so they never clobber the
    /// session that gets restored on the next launch.
    var persistsSession = false
    var childCache: [FileTreeCacheKey: [FileNode]] = [:]
    var watchers: [EditorTab.ID: FileWatcher] = [:]

    init() {
        WorkspaceRegistry.register(self)
    }

    /// Starts the primary window session. It always records later folder/tab
    /// changes, but restore is controlled by the user's startup preference.
    func startPrimarySession(restoreLastWorkspace: Bool) async {
        persistsSession = true
        guard restoreLastWorkspace else { return }
        if let path = UserDefaults.standard.string(forKey: Keys.lastWorkspaceRoot) {
            let url = URL(fileURLWithPath: path)
            if FileManager.default.fileExists(atPath: url.path) {
                rootURL = url
                expandedDirectories = [url]
                RecentWorkspacesStore.shared.record(url)
            }
        }
        await restoreSession()
    }

    var hasUnsavedChanges: Bool {
        tabs.contains { $0.document.isDirty }
    }

    var activeTab: EditorTab? {
        guard let id = activeTabID else { return nil }
        return tabs.first { $0.id == id }
    }

    // MARK: - Session restore

    /// Reopens the file tabs that were open when the app last quit. Skips files
    /// that no longer exist and restores the previously active tab. No-op once
    /// tabs are already present, so it never clobbers a window in use.
    func restoreSession() async {
        guard tabs.isEmpty else { return }
        let defaults = UserDefaults.standard
        let paths = defaults.stringArray(forKey: Keys.openSessionFiles) ?? []
        guard !paths.isEmpty else { return }
        let activePath = defaults.string(forKey: Keys.activeSessionFile)
        for path in paths where FileManager.default.fileExists(atPath: path) {
            await openFile(at: URL(fileURLWithPath: path))
        }
        if let activePath, let match = tabs.first(where: { $0.document.fileURL?.path == activePath }) {
            activeTabID = match.id
        }
        persistSession()
    }

    /// Records the open file tabs and active tab so the next launch can restore
    /// them. Untitled (URL-less) and the encoding of each tab are intentionally
    /// not persisted — only on-disk files come back.
    func persistSession() {
        guard persistsSession else { return }
        let defaults = UserDefaults.standard
        defaults.set(tabs.compactMap { $0.document.fileURL?.path }, forKey: Keys.openSessionFiles)
        if let activePath = activeTab?.document.fileURL?.path {
            defaults.set(activePath, forKey: Keys.activeSessionFile)
        } else {
            defaults.removeObject(forKey: Keys.activeSessionFile)
        }
    }

    enum Keys {
        static let lastWorkspaceRoot = "workspace.lastRoot"
        static let openSessionFiles = "session.openFiles"
        static let activeSessionFile = "session.activeFile"
    }

    struct FileTreeCacheKey: Hashable {
        let url: URL
        let includeHidden: Bool
    }
}
