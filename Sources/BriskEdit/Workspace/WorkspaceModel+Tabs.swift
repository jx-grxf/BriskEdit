import AppKit
import Foundation

// Tab lifecycle: opening, closing, selecting and saving editor tabs.
extension WorkspaceModel {
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
        let doc = TextDocument.empty()
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

    func closeTab(_ id: EditorTab.ID) {
        guard let index = tabs.firstIndex(where: { $0.id == id }) else { return }
        if splitPreviewContent == .markdown(id) {
            splitPreviewContent = nil
        }
        stopWatching(id)
        releaseLSP(tabs[index])
        tabs.remove(at: index)
        if activeTabID == id {
            let fallback = tabs.indices.contains(index) ? tabs[index] : tabs.last
            activeTabID = fallback?.id
        }
        persistSession()
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
        startWatching(tab)
        persistSession()
    }

    func selectTab(_ id: EditorTab.ID) {
        activeTabID = id
        selectedSidebarURL = tabs.first { $0.id == id }?.document.fileURL
        persistSession()
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
            // Saving changes the working tree — refresh git decorations + the
            // Source Control pane so the new modified/added state shows at once.
            NotificationCenter.default.post(name: .gitDidChange, object: nil)
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
        let oldURL = tab.document.fileURL
        let oldLanguage = tab.document.language
        do {
            try await tab.document.save(to: url)
            releaseLSPIfNeeded(uri: oldURL?.absoluteString, language: oldLanguage, replacementURL: url)
            startWatching(tab)
            persistSession()
            await checkActiveDocument()
            NotificationCenter.default.post(name: .gitDidChange, object: nil)
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
