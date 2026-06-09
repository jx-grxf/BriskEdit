import Foundation

// External-change watching (vnode watchers) and language-server lifecycle.
extension WorkspaceModel {
    /// Starts (or replaces) a vnode watcher for a file-backed tab so external
    /// edits get picked up. Preview tabs are skipped — their native viewers reload themselves.
    func startWatching(_ tab: EditorTab) {
        guard tab.previewKind == nil, let url = tab.document.fileURL else { return }
        let id = tab.id
        watchers[id]?.cancel()
        watchers[id] = FileWatcher(url: url) { [weak self] in
            Task { @MainActor in await self?.handleExternalChange(id) }
        }
    }

    func stopWatching(_ id: EditorTab.ID) {
        watchers[id]?.cancel()
        watchers[id] = nil
    }

    /// Unregisters the closed tab from the language server: drops its diagnostics
    /// handler and sends `didClose`. Only for file-backed tabs with an LSP.
    func releaseLSP(_ tab: EditorTab) {
        guard tab.previewKind == nil, let url = tab.document.fileURL,
              LSPService.config(for: tab.document.language) != nil else { return }
        // Skip if the same file is still open in another tab of this window.
        if tabs.contains(where: { $0.id != tab.id && $0.document.fileURL == url }) { return }
        let uri = url.absoluteString
        let language = tab.document.language
        LSPDiagnosticsBus.shared.removeHandler(uri: uri)
        Task { await LSPService.shared.didClose(language: language, uri: uri) }
    }

    func releaseLSPIfNeeded(uri: String?, language: SourceLanguage, replacementURL: URL?) {
        guard let uri,
              replacementURL?.absoluteString != uri,
              LSPService.config(for: language) != nil else { return }
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
}
