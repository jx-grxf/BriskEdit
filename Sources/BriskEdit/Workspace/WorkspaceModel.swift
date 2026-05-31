import AppKit
import Foundation
import Observation

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
    var selectedSidebarURL: URL?
    var lastError: String?
    /// Directories the user has expanded in the file tree — kept here (not in
    /// per-row @State) so the tree survives reloads without collapsing.
    var expandedDirectories: Set<URL> = []
    /// When set, a native preview is shown in a resizable pane beside the editor.
    var splitPreviewKind: PreviewKind?
    /// Open terminal sessions (VS Code-style). Each stays alive while the panel
    /// is shown; the list lets the user add, switch and close them.
    var terminals: [TerminalController] = []
    var activeTerminalID: TerminalController.ID?
    /// Only the primary window persists its folder + open tabs to the shared
    /// defaults; secondary windows are ephemeral so they never clobber the
    /// session that gets restored on the next launch.
    private var persistsSession = false
    private var childCache: [FileTreeCacheKey: [FileNode]] = [:]
    private var watchers: [EditorTab.ID: FileWatcher] = [:]

    init() {
        WorkspaceRegistry.register(self)
    }

    /// Restores the last opened folder and file tabs. Called only for the
    /// primary window; also flips on session persistence for this model.
    func restoreWorkspace() async {
        persistsSession = true
        if let path = UserDefaults.standard.string(forKey: Keys.lastWorkspaceRoot) {
            let url = URL(fileURLWithPath: path)
            if FileManager.default.fileExists(atPath: url.path) {
                rootURL = url
                expandedDirectories = [url]
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

    func openFile(at url: URL) async {
        if let existing = tabs.first(where: { $0.document.fileURL == url }) {
            activeTabID = existing.id
            persistSession()
            return
        }
        if let previewKind = PreviewKind.previewKind(for: url) {
            openTab(EditorTab.preview(previewKind))
            return
        }
        do {
            let doc = try await TextDocument.load(from: url)
            let tab = EditorTab(document: doc)
            if tabs.count == 1,
               let current = tabs.first,
               current.document.fileURL == nil,
               current.document.text.isEmpty,
               !current.document.isDirty {
                tabs = [tab]
            } else {
                tabs.append(tab)
            }
            activeTabID = tab.id
            startWatching(tab)
            persistSession()
        } catch {
            NSLog("BriskEdit: failed to load %@: %@", url.path, String(describing: error))
            lastError = "Could not open \(url.lastPathComponent): \(error.localizedDescription)"
        }
    }

    /// Adds a tab, replacing a lone pristine "Untitled" tab if present.
    private func openTab(_ tab: EditorTab) {
        if tabs.count == 1,
           let current = tabs.first,
           current.document.fileURL == nil,
           current.document.text.isEmpty,
           !current.document.isDirty,
           current.previewKind == nil {
            tabs = [tab]
        } else {
            tabs.append(tab)
        }
        activeTabID = tab.id
        persistSession()
    }

    func ensureInitialDocument() {
        if tabs.isEmpty {
            newUntitled()
        }
    }

    func newUntitled() {
        let doc = TextDocument.empty()
        let tab = EditorTab(document: doc)
        tabs.append(tab)
        activeTabID = tab.id
    }

    func closeTab(_ id: EditorTab.ID) {
        guard let index = tabs.firstIndex(where: { $0.id == id }) else { return }
        stopWatching(id)
        releaseLSP(tabs[index])
        tabs.remove(at: index)
        if activeTabID == id {
            let fallback = tabs.indices.contains(index) ? tabs[index] : tabs.last
            activeTabID = fallback?.id
        }
        persistSession()
    }

    func selectTab(_ id: EditorTab.ID) {
        activeTabID = id
        selectedSidebarURL = tabs.first { $0.id == id }?.document.fileURL
        persistSession()
    }

    /// Closes a tab, prompting to save when it has unsaved edits.
    func requestCloseTab(_ id: EditorTab.ID) {
        guard let tab = tabs.first(where: { $0.id == id }) else { return }
        guard tab.previewKind == nil, tab.document.isDirty else {
            closeTab(id)
            return
        }
        let alert = NSAlert()
        alert.messageText = "Do you want to save the changes you made to “\(tab.document.displayName)”?"
        alert.informativeText = "Your changes will be lost if you don't save them."
        alert.addButton(withTitle: "Save")
        alert.addButton(withTitle: "Don't Save")
        alert.addButton(withTitle: "Cancel")
        switch alert.runModal() {
        case .alertFirstButtonReturn:
            Task {
                if await save(tab) { closeTab(id) }
            }
        case .alertSecondButtonReturn:
            closeTab(id)
        default:
            break
        }
    }

    func toggleSplitPreview(_ kind: PreviewKind) {
        splitPreviewKind = (splitPreviewKind == kind) ? nil : kind
    }

    /// Saves every dirty tab; returns false if the user cancels a Save dialog.
    func saveAllForQuit() async -> Bool {
        for tab in tabs where tab.document.isDirty {
            if await save(tab) == false { return false }
        }
        return true
    }

    @discardableResult
    private func save(_ tab: EditorTab) async -> Bool {
        if tab.document.fileURL == nil {
            let panel = NSSavePanel()
            panel.nameFieldStringValue = tab.document.displayName
            guard panel.runModal() == .OK, let url = panel.url else { return false }
            do {
                try await tab.document.save(to: url)
                return true
            } catch {
                lastError = "Could not save \(tab.document.displayName): \(error.localizedDescription)"
                return false
            }
        }
        await formatBeforeSave(tab.document)
        do {
            try await tab.document.save()
            return true
        } catch {
            lastError = "Could not save \(tab.document.displayName): \(error.localizedDescription)"
            return false
        }
    }

    func setWorkspaceRoot(_ url: URL) {
        rootURL = url
        selectedSidebarURL = nil
        expandedDirectories = [url]
        childCache.removeAll(keepingCapacity: true)
        reloadToken = UUID()
        activeTerminal?.relocate(to: url)
        if persistsSession {
            UserDefaults.standard.set(url.path, forKey: Keys.lastWorkspaceRoot)
        }
    }

    func closeFolder() {
        rootURL = nil
        selectedSidebarURL = nil
        expandedDirectories.removeAll()
        childCache.removeAll(keepingCapacity: true)
        splitPreviewKind = nil
        reloadToken = UUID()
        if persistsSession {
            UserDefaults.standard.removeObject(forKey: Keys.lastWorkspaceRoot)
        }
    }

    func refreshFileTree() {
        childCache.removeAll(keepingCapacity: true)
        reloadToken = UUID()
    }

    func toggleHiddenFiles() {
        showHiddenFiles.toggle()
        childCache.removeAll(keepingCapacity: true)
        reloadToken = UUID()
    }

    /// Flat list of files under the workspace root for the go-to-file palette.
    /// Reuses the file tree's ignore rules (VCS/build/dependency dirs, dotfiles).
    func collectWorkspaceFiles(limit: Int = 8000) async -> [URL] {
        guard let root = rootURL else { return [] }
        let includeHidden = showHiddenFiles
        return await Task.detached(priority: .userInitiated) {
            FileIndex.files(under: root, includeHidden: includeHidden, limit: limit)
        }.value
    }

    func loadChildren(of url: URL) async -> [FileNode] {
        let key = FileTreeCacheKey(url: url, includeHidden: showHiddenFiles)
        if let cached = childCache[key] {
            return cached
        }
        let includeHidden = showHiddenFiles
        let loaded = await Task.detached(priority: .userInitiated) {
            FileNode.children(of: url, includeHidden: includeHidden)
        }.value
        childCache[key] = loaded
        return loaded
    }

    /// Runs a syntax/type check on the active document and stores the findings
    /// for the gutter. No-op for languages without a check driver.
    func checkActiveDocument() async {
        guard let doc = activeTab?.document else { return }
        if let diagnostics = await DiagnosticsService.check(text: doc.text, language: doc.language, fileURL: doc.fileURL) {
            doc.diagnostics = diagnostics
        }
    }

    func runActiveDocument() {
        showTerminal = true
        ensureTerminal().runActiveDocument(activeTab?.document, workspaceRoot: rootURL)
        Task { await checkActiveDocument() }
    }

    // MARK: - Terminal sessions

    var activeTerminal: TerminalController? {
        if let id = activeTerminalID, let match = terminals.first(where: { $0.id == id }) {
            return match
        }
        return terminals.first
    }

    /// Returns the active session, creating the first one on demand.
    @discardableResult
    func ensureTerminal() -> TerminalController {
        if let active = activeTerminal { return active }
        return addTerminal()
    }

    @discardableResult
    func addTerminal() -> TerminalController {
        let controller = TerminalController()
        controller.name = nextTerminalName()
        terminals.append(controller)
        activeTerminalID = controller.id
        controller.startShell(cwd: rootURL)
        return controller
    }

    func selectTerminal(_ id: TerminalController.ID) {
        guard terminals.contains(where: { $0.id == id }) else { return }
        activeTerminalID = id
    }

    func closeTerminal(_ id: TerminalController.ID) {
        guard let index = terminals.firstIndex(where: { $0.id == id }) else { return }
        terminals.remove(at: index)
        if activeTerminalID == id {
            let fallback = min(index, terminals.count - 1)
            activeTerminalID = terminals.indices.contains(fallback) ? terminals[fallback].id : nil
        }
    }

    /// Names sessions zsh, zsh 2, zsh 3 … reusing the lowest free number so the
    /// list stays tidy after closing tabs in the middle.
    private func nextTerminalName() -> String {
        let base = (ProcessInfo.processInfo.environment["SHELL"]
            .map { URL(fileURLWithPath: $0).lastPathComponent }) ?? "zsh"
        let used = Set(terminals.map(\.name))
        if !used.contains(base) { return base }
        var n = 2
        while used.contains("\(base) \(n)") { n += 1 }
        return "\(base) \(n)"
    }

    /// Runs the configured on-save formatter over the buffer, if enabled and a
    /// formatter is available. No-op otherwise. Preferences are read straight
    /// from UserDefaults so the model stays decoupled from the Preferences view.
    private func formatBeforeSave(_ document: TextDocument) async {
        guard UserDefaults.standard.bool(forKey: "editor.formatOnSave") else { return }
        if let formatted = await FormatterService.format(text: document.text, language: document.language, fileURL: document.fileURL) {
            document.applyFormatted(formatted)
        }
    }

    func saveActiveTab() async {
        guard let tab = activeTab else { return }
        if tab.document.fileURL == nil {
            await saveActiveTabAs()
            return
        }
        await formatBeforeSave(tab.document)
        do {
            try await tab.document.save()
            await checkActiveDocument()
        } catch {
            NSLog("BriskEdit: save failed: %@", String(describing: error))
            lastError = "Could not save \(tab.document.displayName): \(error.localizedDescription)"
        }
    }

    func saveActiveTabAs() async {
        guard let tab = activeTab else { return }
        let panel = NSSavePanel()
        panel.nameFieldStringValue = tab.document.displayName
        guard panel.runModal() == .OK, let url = panel.url else { return }
        await formatBeforeSave(tab.document)
        do {
            try await tab.document.save(to: url)
            persistSession()
        } catch {
            NSLog("BriskEdit: save-as failed: %@", String(describing: error))
            lastError = "Could not save \(tab.document.displayName): \(error.localizedDescription)"
        }
    }

    // MARK: - External change watching

    /// Starts (or replaces) a vnode watcher for a file-backed tab so external
    /// edits get picked up. Preview tabs are skipped — their native viewers reload themselves.
    private func startWatching(_ tab: EditorTab) {
        guard tab.previewKind == nil, let url = tab.document.fileURL else { return }
        let id = tab.id
        watchers[id]?.cancel()
        watchers[id] = FileWatcher(url: url) { [weak self] in
            Task { @MainActor in await self?.handleExternalChange(id) }
        }
    }

    private func stopWatching(_ id: EditorTab.ID) {
        watchers[id]?.cancel()
        watchers[id] = nil
    }

    /// Unregisters the closed tab from the language server: drops its diagnostics
    /// handler and sends `didClose`. Only for file-backed tabs with an LSP.
    private func releaseLSP(_ tab: EditorTab) {
        guard tab.previewKind == nil, let url = tab.document.fileURL,
              LSPService.config(for: tab.document.language) != nil else { return }
        // Skip if the same file is still open in another tab of this window.
        if tabs.contains(where: { $0.id != tab.id && $0.document.fileURL == url }) { return }
        let uri = url.absoluteString
        let language = tab.document.language
        LSPDiagnosticsBus.shared.removeHandler(uri: uri)
        Task { await LSPService.shared.didClose(language: language, uri: uri) }
    }

    /// Reloads a clean buffer from disk; flags a dirty buffer for the reload
    /// banner instead of clobbering unsaved edits. Our own saves land here too,
    /// but disk == buffer then, so they're a no-op.
    private func handleExternalChange(_ id: EditorTab.ID) async {
        guard let tab = tabs.first(where: { $0.id == id }), let url = tab.document.fileURL else { return }
        guard FileManager.default.fileExists(atPath: url.path) else { return }
        let disk = await Task.detached(priority: .utility) { () -> String? in
            var used: String.Encoding = .utf8
            return try? String(contentsOf: url, usedEncoding: &used)
        }.value
        guard let disk, disk != tab.document.text else { return }
        if tab.document.isDirty {
            tab.document.externalChangePending = true
        } else {
            await tab.document.reloadFromDisk()
        }
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
    private func persistSession() {
        guard persistsSession else { return }
        let defaults = UserDefaults.standard
        defaults.set(tabs.compactMap { $0.document.fileURL?.path }, forKey: Keys.openSessionFiles)
        if let activePath = activeTab?.document.fileURL?.path {
            defaults.set(activePath, forKey: Keys.activeSessionFile)
        } else {
            defaults.removeObject(forKey: Keys.activeSessionFile)
        }
    }

    // MARK: - File operations

    /// Folder a new file/folder lands in: the selected directory, the parent of
    /// the selected file, or — when nothing is selected (e.g. the user clicked
    /// the empty area of the file tree) — the workspace root.
    var currentDirectory: URL? {
        if let selected = selectedSidebarURL {
            let isDirectory = (try? selected.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true
            return isDirectory ? selected : selected.deletingLastPathComponent()
        }
        return rootURL
    }

    func promptNewFile(in directory: URL? = nil) {
        guard let dir = directory ?? currentDirectory else { return }
        guard let name = promptForName(title: "New File", message: "Create a file in “\(dir.lastPathComponent)”", placeholder: "untitled.c", defaultValue: "") else { return }
        let url = dir.appendingPathComponent(name)
        guard !FileManager.default.fileExists(atPath: url.path) else {
            lastError = "“\(name)” already exists."
            return
        }
        do {
            try Data().write(to: url)
            expandedDirectories.insert(dir)
            refreshFileTree()
            selectedSidebarURL = url
            Task { await openFile(at: url) }
        } catch {
            lastError = "Could not create \(name): \(error.localizedDescription)"
        }
    }

    func promptNewFolder(in directory: URL? = nil) {
        guard let dir = directory ?? currentDirectory else { return }
        guard let name = promptForName(title: "New Folder", message: "Create a folder in “\(dir.lastPathComponent)”", placeholder: "untitled folder", defaultValue: "") else { return }
        let url = dir.appendingPathComponent(name, isDirectory: true)
        guard !FileManager.default.fileExists(atPath: url.path) else {
            lastError = "“\(name)” already exists."
            return
        }
        do {
            try FileManager.default.createDirectory(at: url, withIntermediateDirectories: false)
            expandedDirectories.insert(dir)
            expandedDirectories.insert(url)
            refreshFileTree()
            selectedSidebarURL = url
        } catch {
            lastError = "Could not create \(name): \(error.localizedDescription)"
        }
    }

    func deleteFile(_ url: URL) {
        let alert = NSAlert()
        alert.messageText = "Move “\(url.lastPathComponent)” to Trash?"
        alert.informativeText = "You can restore it from the Trash."
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Move to Trash")
        alert.addButton(withTitle: "Cancel")
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        do {
            try FileManager.default.trashItem(at: url, resultingItemURL: nil)
            closeTabs(referencing: url)
            refreshFileTree()
        } catch {
            lastError = "Could not delete \(url.lastPathComponent): \(error.localizedDescription)"
        }
    }

    func duplicateFile(_ url: URL) {
        let fm = FileManager.default
        let ext = url.pathExtension
        let base = url.deletingPathExtension().lastPathComponent
        let dir = url.deletingLastPathComponent()
        var candidate = dir.appendingPathComponent(ext.isEmpty ? "\(base) copy" : "\(base) copy.\(ext)")
        var index = 2
        while fm.fileExists(atPath: candidate.path) {
            candidate = dir.appendingPathComponent(ext.isEmpty ? "\(base) copy \(index)" : "\(base) copy \(index).\(ext)")
            index += 1
        }
        do {
            try fm.copyItem(at: url, to: candidate)
            refreshFileTree()
        } catch {
            lastError = "Could not duplicate \(url.lastPathComponent): \(error.localizedDescription)"
        }
    }

    func renameFile(_ url: URL) {
        guard let name = promptForName(title: "Rename", message: "Rename “\(url.lastPathComponent)”", placeholder: "", defaultValue: url.lastPathComponent), name != url.lastPathComponent else { return }
        let destination = url.deletingLastPathComponent().appendingPathComponent(name)
        guard !FileManager.default.fileExists(atPath: destination.path) else {
            lastError = "“\(name)” already exists."
            return
        }
        do {
            try FileManager.default.moveItem(at: url, to: destination)
            retargetTabs(from: url, to: destination)
            persistSession()
            refreshFileTree()
            selectedSidebarURL = destination
        } catch {
            lastError = "Could not rename \(url.lastPathComponent): \(error.localizedDescription)"
        }
    }

    /// Handles a drop onto a folder in the tree: files already inside the
    /// workspace are moved, files coming from outside (Finder, Downloads, …) are
    /// copied in.
    @discardableResult
    func handleTreeDrop(_ urls: [URL], into directory: URL) -> Bool {
        let root = rootURL?.standardizedFileURL.path
        var changed = false
        for url in urls {
            let inside = root.map { url.standardizedFileURL.path.hasPrefix($0 + "/") } ?? false
            if inside {
                if moveFile(url, into: directory) { changed = true }
            } else if importExternalFile(url, into: directory) != nil {
                changed = true
            }
        }
        return changed
    }

    /// Copies an external file/folder into `directory`, disambiguating the name.
    @discardableResult
    func importExternalFile(_ source: URL, into directory: URL) -> URL? {
        let fm = FileManager.default
        var destination = directory.appendingPathComponent(source.lastPathComponent)
        if fm.fileExists(atPath: destination.path) {
            let base = source.deletingPathExtension().lastPathComponent
            let ext = source.pathExtension
            var index = 2
            repeat {
                destination = directory.appendingPathComponent(ext.isEmpty ? "\(base) \(index)" : "\(base) \(index).\(ext)")
                index += 1
            } while fm.fileExists(atPath: destination.path)
        }
        do {
            try fm.copyItem(at: source, to: destination)
            expandedDirectories.insert(directory)
            refreshFileTree()
            return destination
        } catch {
            lastError = "Could not import \(source.lastPathComponent): \(error.localizedDescription)"
            return nil
        }
    }

    /// Handles files dropped onto the editor/workspace area: directories become
    /// the workspace root, files are opened in tabs.
    func openDropped(_ urls: [URL]) {
        for url in urls {
            let isDirectory = (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true
            if isDirectory {
                setWorkspaceRoot(url)
            } else {
                Task { await openFile(at: url) }
            }
        }
    }

    /// Moves a file/folder into `directory` (drag & drop in the file tree).
    @discardableResult
    func moveFile(_ source: URL, into directory: URL) -> Bool {
        let src = source.standardizedFileURL
        let dir = directory.standardizedFileURL
        // No-op when dropped onto its own folder, and never move a folder into
        // itself or one of its descendants.
        guard src.deletingLastPathComponent() != dir else { return false }
        guard dir != src, !dir.path.hasPrefix(src.path + "/") else { return false }

        let destination = dir.appendingPathComponent(src.lastPathComponent)
        guard !FileManager.default.fileExists(atPath: destination.path) else {
            lastError = "“\(src.lastPathComponent)” already exists in \(dir.lastPathComponent)."
            return false
        }
        do {
            try FileManager.default.moveItem(at: src, to: destination)
            retargetTabs(from: src, to: destination)
            refreshFileTree()
            return true
        } catch {
            lastError = "Could not move \(src.lastPathComponent): \(error.localizedDescription)"
            return false
        }
    }

    func revealInFinder(_ url: URL) {
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    func copyToPasteboard(_ string: String) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(string, forType: .string)
    }

    func relativePath(of url: URL) -> String {
        guard let root = rootURL else { return url.path }
        if url.path.hasPrefix(root.path) {
            let trimmed = url.path.dropFirst(root.path.count)
            return trimmed.hasPrefix("/") ? String(trimmed.dropFirst()) : String(trimmed)
        }
        return url.path
    }

    private func promptForName(title: String, message: String, placeholder: String, defaultValue: String) -> String? {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 260, height: 24))
        field.placeholderString = placeholder
        field.stringValue = defaultValue
        alert.accessoryView = field
        alert.addButton(withTitle: "OK")
        alert.addButton(withTitle: "Cancel")
        alert.window.initialFirstResponder = field
        guard alert.runModal() == .alertFirstButtonReturn else { return nil }
        let trimmed = field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private func closeTabs(referencing url: URL) {
        for tab in tabs where tab.document.fileURL?.standardizedFileURL == url.standardizedFileURL {
            closeTab(tab.id)
        }
    }

    private func retargetTabs(from oldURL: URL, to newURL: URL) {
        for tab in tabs where tab.document.fileURL?.standardizedFileURL == oldURL.standardizedFileURL {
            tab.document.retarget(to: newURL)
            startWatching(tab)
        }
    }

    private enum Keys {
        static let lastWorkspaceRoot = "workspace.lastRoot"
        static let openSessionFiles = "session.openFiles"
        static let activeSessionFile = "session.activeFile"
    }

    private struct FileTreeCacheKey: Hashable {
        let url: URL
        let includeHidden: Bool
    }
}
