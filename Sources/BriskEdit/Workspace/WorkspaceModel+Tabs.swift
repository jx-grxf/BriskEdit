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

    func requestCloseOtherTabs(keeping id: EditorTab.ID) {
        for tab in tabs where tab.id != id {
            requestCloseTab(tab.id)
        }
    }

    func requestCloseTabsToRight(of id: EditorTab.ID) {
        guard let index = tabs.firstIndex(where: { $0.id == id }) else { return }
        for tab in tabs.dropFirst(index + 1) {
            requestCloseTab(tab.id)
        }
    }

    func requestCloseAllTabs() {
        for tab in tabs {
            requestCloseTab(tab.id)
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
