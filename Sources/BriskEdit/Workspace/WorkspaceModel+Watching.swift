import Foundation

// External-change watching (vnode watchers) and language-server lifecycle.
extension WorkspaceModel {
    /// Starts (or replaces) a vnode watcher for a file-backed tab so external
    /// edits get picked up. Preview tabs are skipped — their native viewers reload themselves.
    func startWatching(_ tab: EditorTab) {
        guard tab.previewKind == nil, let url = tab.document.fileURL else { return }
        let id = tab.id
        LSPService.retainDocument(owner: id, language: tab.document.language, uri: url.absoluteString)
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
        guard tab.previewKind == nil, let url = tab.document.fileURL else { return }
        let uri = url.absoluteString
        let language = tab.document.language
        Task { await LSPService.shared.releaseDocument(owner: tab.id, language: language, uri: uri) }
    }

    func releaseLSPIfNeeded(uri: String?, language: SourceLanguage, replacementURL: URL?) {
        guard let uri,
              replacementURL?.absoluteString != uri else { return }
        guard let replacementURL,
              let owner = tabs.first(where: { $0.document.fileURL == replacementURL })?.id else { return }
        Task { await LSPService.shared.releaseDocument(owner: owner, language: language, uri: uri) }
    }

    /// Releases every tab owned by this window. WindowConfigurator calls this
    /// from the native window-close callback, where view disappearance would be
    /// too broad (tabs also disappear during ordinary SwiftUI transitions).
    func releaseAllLSPDocuments() {
        let documents = tabs.compactMap { tab -> (UUID, SourceLanguage, String)? in
            guard tab.previewKind == nil, let url = tab.document.fileURL else { return nil }
            return (tab.id, tab.document.language, url.absoluteString)
        }
        Task {
            for (owner, language, uri) in documents {
                await LSPService.shared.releaseDocument(owner: owner, language: language, uri: uri)
            }
        }
    }

    /// Reloads a clean buffer from disk; flags a dirty buffer for the reload
    /// banner instead of clobbering unsaved edits. Events caused by our own
    /// saves are skipped, and a vanished file closes the tab — or flags it when
    /// unsaved edits remain.
    private func handleExternalChange(_ id: EditorTab.ID) async {
        guard let tab = tabs.first(where: { $0.id == id }), let url = tab.document.fileURL else { return }
        guard FileManager.default.fileExists(atPath: url.path) else {
            if tab.document.isDirty {
                tab.document.externalChangePending = true
            } else {
                closeTab(id)
            }
            return
        }
        // An atomic save replaces the file and fires this watcher. Identical
        // size+mtime right after our own write means the event was ours — and
        // stat is far cheaper than decoding the file just to diff it.
        if let written = tab.document.lastSelfWriteInfo,
           let values = try? url.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey]),
           values.fileSize == written.size,
           values.contentModificationDate == written.modificationDate {
            return
        }
        let disk = await Task.detached(priority: .utility) { () -> (oversized: Bool, content: String?) in
            // Same safety cap as TextDocument.load: a file that grew past the
            // editing limit (e.g. a log another process appends to) must not be
            // slurped into memory on every FS event just to diff it.
            if let size = try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize,
               Int64(size) > TextDocument.maximumEditableFileBytes {
                return (true, nil)
            }
            var used: String.Encoding = .utf8
            return (false, try? String(contentsOf: url, usedEncoding: &used))
        }.value
        if disk.oversized {
            tab.document.externalChangePending = true
            return
        }
        guard let disk = disk.content, disk != tab.document.text else { return }
        if tab.document.isDirty {
            tab.document.externalChangePending = true
        } else {
            await tab.document.reloadFromDisk()
        }
    }
}
