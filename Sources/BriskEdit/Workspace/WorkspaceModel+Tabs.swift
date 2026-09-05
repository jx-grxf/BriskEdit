import AppKit
import Foundation

// Tab lifecycle: opening, closing, selecting and saving editor tabs.
extension WorkspaceModel {
    /// Routes deferred-autosave failures into the workspace's usual error
    /// message so they aren't dropped silently.
    private func observeAutosaveFailures(of document: TextDocument) {
        document.autosaveFailureHandler = { [weak self, weak document] error in
            guard let document else { return }
            self?.lastError = "Could not autosave \(document.displayName): \(error.localizedDescription)"
        }
    }

    func openFile(at url: URL) async {
        markUserInteraction()
        // Every open (new tab, re-focus of an existing tab, preview) makes this
        // the most recently used file for File ▸ Open Recent.
        RecentWorkspacesStore.shared.recordFile(url)
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
            observeAutosaveFailures(of: doc)
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

    /// Opens a file and scrolls to / selects a 1-based line/column target — used
    /// by Find in Files, the symbol outline and go-to-definition.
    func openFile(at url: URL, line: Int, column: Int = 1, length: Int = 0) async {
        await openFile(at: url)
        guard let doc = tabs.first(where: { $0.document.fileURL == url })?.document else { return }
        doc.requestReveal(line: line, column: column, length: length)
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
        markUserInteraction()
        let doc = TextDocument.empty()
        observeAutosaveFailures(of: doc)
        let tab = EditorTab(document: doc)
        tabs.append(tab)
        activeTabID = tab.id
    }

    /// Opens (or re-focuses) the built-in "What's New" page as a tab.
    func showWhatsNew(version: String) {
        if let existing = tabs.first(where: {
            if case .whatsNew = $0.special { return true }
            return false
        }) {
            activeTabID = existing.id
            return
        }
        let tab = EditorTab.whatsNew(version: version)
        tabs.append(tab)
        activeTabID = tab.id
    }

    /// Reopens the most recently closed file tab (⇧⌘T), selecting it once
    /// loaded. Every removal path funnels through `closeTab` — user closes,
    /// folder-delete and the watcher auto-closing a clean vanished tab — so all
    /// of them land here. Tear-off moves don't: the tab keeps living, just in
    /// another window.
    func reopenClosedTab() {
        guard let url = ClosedTabHistory.shared.pop() else { return }
        guard FileManager.default.fileExists(atPath: url.path) else {
            lastError = "Could not reopen \(url.lastPathComponent): the file no longer exists."
            return
        }
        Task { await openFile(at: url) }
    }

    func closeTab(_ id: EditorTab.ID) {
        TabTearOffCoordinator.shared.cancelDrag(tabID: id)
        guard let index = tabs.firstIndex(where: { $0.id == id }) else { return }
        if let url = tabs[index].document.fileURL {
            ClosedTabHistory.shared.record(url)
        }
        if splitPreviewContent == .markdown(id) {
            splitPreviewContent = nil
        }
        tabs[index].document.discardRecoverySnapshot()
        stopWatching(id)
        releaseLSP(tabs[index])
        tabs[index].document.invalidatePendingSaves()
        tabs.remove(at: index)
        if activeTabID == id {
            let fallback = tabs.indices.contains(index) ? tabs[index] : tabs.last
            activeTabID = fallback?.id
        }
        persistSession()
    }

    func discardDraftsForWindowClose() async {
        for tab in tabs { tab.document.discardRecoverySnapshot() }
        for tab in tabs { await tab.document.flushRecoveryChanges() }
    }

    /// Detaches a tab so it can be re-mounted in another window, keeping the
    /// **live document** — and its unsaved edits, dirty state and language-server
    /// registration — intact. Unlike `closeTab`, it neither prompts to save nor
    /// sends `didClose`: the document is moving, not closing.
    func detachTabForMove(_ id: EditorTab.ID) -> EditorTab? {
        guard let index = tabs.firstIndex(where: { $0.id == id }) else { return nil }
        let tab = tabs[index]
        if splitPreviewContent == .markdown(id) { splitPreviewContent = nil }
        stopWatching(id)
        tabs.remove(at: index)
        if activeTabID == id {
            let fallback = tabs.indices.contains(index) ? tabs[index] : tabs.last
            activeTabID = fallback?.id
        }
        persistSession()
        return tab
    }

    /// Adopts a tab torn off another window: inherits that window's folder so the
    /// sidebar and breadcrumbs still resolve, then makes the tab the sole, active
    /// tab. The document object (with any unsaved edits) is reused as-is.
    func adoptTornOffTab(_ tab: EditorTab, rootURL: URL?) {
        if let rootURL {
            self.rootURL = rootURL
            expandedDirectories = [rootURL]
            RecentWorkspacesStore.shared.record(rootURL)
        }
        tabs = [tab]
        activeTabID = tab.id
        observeAutosaveFailures(of: tab.document)
        startWatching(tab)
    }

    /// Accepts a tab moved in from another window: replaces a lone pristine
    /// "Untitled"/welcome tab if present (so dropping onto an empty window doesn't
    /// leave a stray blank tab), otherwise appends. Becomes the active tab.
    func acceptMovedTab(_ tab: EditorTab) {
        if tabs.count == 1,
           let current = tabs.first,
           current.previewKind == nil,
           current.special == nil,
           current.document.fileURL == nil,
           current.document.text.isEmpty,
           !current.document.isDirty {
            tabs = [tab]
        } else {
            tabs.append(tab)
        }
        activeTabID = tab.id
        observeAutosaveFailures(of: tab.document)
        startWatching(tab)
        persistSession()
    }

    func selectTab(_ id: EditorTab.ID) {
        guard let tab = tabs.first(where: { $0.id == id }) else { return }
        activeTabID = id
        selectedSidebarURL = tab.document.fileURL
        persistSession()
    }

    func selectAdjacentTab(offset: Int) {
        guard !tabs.isEmpty, let activeTabID,
              let index = tabs.firstIndex(where: { $0.id == activeTabID }) else { return }
        let next = (index + offset % tabs.count + tabs.count) % tabs.count
        selectTab(tabs[next].id)
    }

    /// Reorders an open tab so it lands at the slot held by `targetID` — the
    /// in-strip drag-to-reorder action. Dragging a tab rightwards drops it *after*
    /// the target, leftwards *before* it, matching the visual "this tab takes that
    /// slot" expectation. No-op if either id is unknown or they're the same.
    func moveTab(_ id: EditorTab.ID, toPositionOf targetID: EditorTab.ID) {
        guard id != targetID,
              let from = tabs.firstIndex(where: { $0.id == id }),
              let target = tabs.firstIndex(where: { $0.id == targetID }) else { return }
        let movingRight = from < target
        let tab = tabs.remove(at: from)
        // The target shifted left if it sat after the removed tab; re-resolve it.
        guard let newTarget = tabs.firstIndex(where: { $0.id == targetID }) else {
            tabs.insert(tab, at: min(from, tabs.count))
            return
        }
        let insertionIndex = movingRight ? newTarget + 1 : newTarget
        tabs.insert(tab, at: min(max(insertionIndex, 0), tabs.count))
        persistSession()
    }

    /// Shifts the active tab one slot left (`-1`) or right (`+1`) — the keyboard
    /// equivalent of dragging it. No-op at the respective end.
    func moveActiveTab(by offset: Int) {
        guard let id = activeTabID,
              let from = tabs.firstIndex(where: { $0.id == id }) else { return }
        let to = from + offset
        guard tabs.indices.contains(to) else { return }
        let tab = tabs.remove(at: from)
        tabs.insert(tab, at: to)
        persistSession()
    }

    /// Inserts a tab moved in from another window *at* the slot held by `targetID`
    /// (the chip it was dropped on), so a cross-window drop honors the drop
    /// position instead of always appending. Replaces a lone pristine Untitled
    /// tab if that's all the target holds. Becomes the active tab.
    func insertMovedTab(_ tab: EditorTab, before targetID: EditorTab.ID) {
        if tabs.count == 1,
           let current = tabs.first,
           current.previewKind == nil,
           current.special == nil,
           current.document.fileURL == nil,
           current.document.text.isEmpty,
           !current.document.isDirty {
            tabs = [tab]
        } else if let index = tabs.firstIndex(where: { $0.id == targetID }) {
            tabs.insert(tab, at: index)
        } else {
            tabs.append(tab)
        }
        activeTabID = tab.id
        observeAutosaveFailures(of: tab.document)
        startWatching(tab)
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

    func requestCloseOtherTabs(keeping id: EditorTab.ID) {
        let ids = tabs.filter { $0.id != id }.map(\.id)
        Task { await closeTabsSequentially(ids) }
    }

    func requestCloseTabsToRight(of id: EditorTab.ID) {
        guard let index = tabs.firstIndex(where: { $0.id == id }) else { return }
        let ids = tabs[(index + 1)...].map(\.id)
        Task { await closeTabsSequentially(ids) }
    }

    func requestCloseAllTabs() {
        let ids = tabs.map(\.id)
        Task { await closeTabsSequentially(ids) }
    }

    /// Closes the given tabs in order, prompting to save each dirty one. Aborts
    /// the rest of the batch the moment the user cancels (or a save fails) — so
    /// "Close Other Tabs" with a Cancel leaves the remaining tabs open, matching
    /// mainstream editors instead of closing them anyway. IDs are snapshotted by
    /// the callers, so concurrent tab mutation can't shift the set mid-loop.
    private func closeTabsSequentially(_ ids: [EditorTab.ID]) async {
        guard !bulkCloseInProgress else { return }
        bulkCloseInProgress = true
        defer { bulkCloseInProgress = false }
        for id in ids {
            guard let tab = tabs.first(where: { $0.id == id }) else { continue }
            guard tab.previewKind == nil, tab.document.isDirty else {
                closeTab(id)
                continue
            }
            let alert = NSAlert()
            alert.messageText = "Do you want to save the changes you made to “\(tab.document.displayName)”?"
            alert.informativeText = "Your changes will be lost if you don't save them."
            alert.addButton(withTitle: "Save")
            alert.addButton(withTitle: "Don't Save")
            alert.addButton(withTitle: "Cancel")
            switch alert.runModal() {
            case .alertFirstButtonReturn:
                if await save(tab) { closeTab(id) } else { return }
            case .alertSecondButtonReturn:
                closeTab(id)
            default:
                return
            }
        }
    }

    func openInSplitScreen(_ url: URL) async {
        if let kind = PreviewKind.previewKind(for: url) {
            let content = SplitPreviewContent.native(kind)
            splitPreviewContent = (splitPreviewContent == content) ? nil : content
            return
        }

        guard SourceLanguage(url: url, displayName: url.lastPathComponent) == .markdown else { return }
        if case .markdown(let id) = splitPreviewContent,
           tabs.first(where: { $0.id == id })?.document.fileURL == url {
            splitPreviewContent = nil
            return
        }

        let previousActiveID = activeTabID
        await openFile(at: url)
        guard let markdownTab = tabs.first(where: { $0.document.fileURL == url }) else { return }
        if let previousActiveID, tabs.contains(where: { $0.id == previousActiveID }) {
            activeTabID = previousActiveID
        }
        splitPreviewContent = .markdown(markdownTab.id)
        persistSession()
    }

    /// Saves every dirty tab; returns false if the user cancels a Save dialog.
    func saveAllForQuit() async -> Bool {
        for tab in tabs where tab.document.isDirty {
            if await save(tab) == false { return false }
        }
        return true
    }

    @discardableResult
    func save(_ tab: EditorTab) async -> Bool {
        if tab.document.fileURL == nil {
            let panel = NSSavePanel()
            panel.nameFieldStringValue = tab.document.displayName
            guard panel.runModal() == .OK, let url = panel.url else { return false }
            do {
                try await tab.document.save(to: url)
                await finishFileBindingSave(tab, oldURL: nil, oldLanguage: tab.document.language)
                return true
            } catch {
                if error is CancellationError { return false }
                lastError = "Could not save \(tab.document.displayName): \(error.localizedDescription)"
                return false
            }
        }
        await formatBeforeSave(tab.document)
        do {
            try await saveResolvingExternalConflict(tab.document)
            return true
        } catch {
            if error is CancellationError { return false }
            lastError = "Could not save \(tab.document.displayName): \(error.localizedDescription)"
            return false
        }
    }

    /// Shared post-write wiring for saves that bind a document to a (new) file:
    /// releases a stale LSP registration, restarts the file watcher, persists the
    /// session and refreshes diagnostics + git decorations.
    private func finishFileBindingSave(_ tab: EditorTab, oldURL: URL?, oldLanguage: SourceLanguage) async {
        releaseLSPIfNeeded(uri: oldURL?.absoluteString, language: oldLanguage, replacementURL: tab.document.fileURL)
        startWatching(tab)
        persistSession()
        await checkActiveDocument()
        NotificationCenter.default.post(name: .gitDidChange, object: nil)
    }

    func saveActiveTab() async {
        guard let tab = activeTab else { return }
        if tab.document.fileURL == nil {
            await saveActiveTabAs()
            return
        }
        await formatBeforeSave(tab.document)
        do {
            try await saveResolvingExternalConflict(tab.document)
            await checkActiveDocument()
            // Saving changes the working tree — refresh git decorations + the
            // Source Control pane so the new modified/added state shows at once.
            NotificationCenter.default.post(name: .gitDidChange, object: nil)
        } catch {
            if error is CancellationError { return }
            NSLog("BriskEdit: save failed: %@", String(describing: error))
            lastError = "Could not save \(tab.document.displayName): \(error.localizedDescription)"
        }
    }

    private func saveResolvingExternalConflict(_ document: TextDocument) async throws {
        guard document.externalChangePending else {
            try await document.save()
            return
        }
        let alert = NSAlert()
        alert.messageText = "“\(document.displayName)” changed on disk."
        alert.informativeText = "Overwrite the external version with your current edits, or cancel and review the conflict."
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Overwrite")
        alert.addButton(withTitle: "Cancel")
        guard alert.runModal() == .alertFirstButtonReturn else { throw CancellationError() }
        try await document.overwriteExternalChange()
    }

    func saveActiveTabAs() async {
        guard let tab = activeTab else { return }
        let panel = NSSavePanel()
        panel.nameFieldStringValue = tab.document.displayName
        guard panel.runModal() == .OK, let url = panel.url else { return }
        await formatBeforeSave(tab.document)
        let oldURL = tab.document.fileURL
        let oldLanguage = tab.document.language
        do {
            try await tab.document.save(to: url)
            await finishFileBindingSave(tab, oldURL: oldURL, oldLanguage: oldLanguage)
        } catch {
            NSLog("BriskEdit: save-as failed: %@", String(describing: error))
            lastError = "Could not save \(tab.document.displayName): \(error.localizedDescription)"
        }
    }

    /// Runs the configured on-save formatter over the buffer, if enabled and a
    /// formatter is available. No-op otherwise. Preferences are read straight
    /// from UserDefaults so the model stays decoupled from the Preferences view.
    private func formatBeforeSave(_ document: TextDocument) async {
        guard UserDefaults.standard.bool(forKey: "editor.formatOnSave") else { return }
        let storedTabWidth = UserDefaults.standard.integer(forKey: "editor.tabWidth")
        let indentWidth = storedTabWidth == 0 ? 4 : storedTabWidth
        let revision = document.revision
        let text = document.text
        if let formatted = await FormatterService.format(text: text, language: document.language, fileURL: document.fileURL, indentWidth: indentWidth),
           document.revision == revision {
            document.applyFormatted(formatted)
        }
    }
}
