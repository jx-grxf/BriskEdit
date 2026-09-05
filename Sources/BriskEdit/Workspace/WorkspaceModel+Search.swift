import AppKit
import Foundation

// Project-wide search/replace (Find in Files) and the symbol outline.
extension WorkspaceModel {
    /// Reveals the search pane and asks it to focus the input (Find in Files).
    func revealSearch() {
        sidebarTab = .search
        focusSearchToken &+= 1
    }

    var searchTotalMatches: Int {
        searchResults.reduce(0) { $0 + $1.matches.count }
    }

    /// Runs the current query across the workspace, replacing any in-flight search.
    func runProjectSearch() {
        searchTask?.cancel()
        guard let root = rootURL, !searchQuery.text.trimmingCharacters(in: .whitespaces).isEmpty else {
            searchResults = []
            searchError = nil
            searchReachedLimit = false
            isSearching = false
            return
        }
        isSearching = true
        let query = searchQuery
        // Search dotfiles too (.gitignore, .env, …); ripgrep still honors
        // .gitignore and we exclude .git, so this only adds meaningful hidden
        // files — independent of the file tree's "show hidden" toggle.
        searchTask = Task { [weak self] in
            let response = await SearchService.searchWithFeedback(query, root: root, includeHidden: true)
            guard let self, !Task.isCancelled else { return }
            self.searchResults = response.results
            self.searchError = response.errorMessage
            self.searchReachedLimit = response.reachedMatchLimit
            self.isSearching = false
        }
    }

    /// Rewrites every match on disk after a confirmation prompt, then re-searches.
    func replaceAllInProject() {
        guard !searchQuery.text.isEmpty, !searchResults.isEmpty else { return }
        let files = searchResults.map(\.url)
        let matches = searchTotalMatches
        let alert = NSAlert()
        alert.messageText = "Replace \(matches) match\(matches == 1 ? "" : "es") across \(files.count) file\(files.count == 1 ? "" : "s")?"
        alert.informativeText = "The files are rewritten on disk. This can't be undone from the editor."
        alert.addButton(withTitle: "Replace All")
        alert.addButton(withTitle: "Cancel")
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        let query = searchQuery
        let replacement = searchReplacement
        Task { [weak self] in
            _ = await SearchService.replaceAll(query, replacement: replacement, in: files)
            self?.runProjectSearch()
        }
    }

    /// Reloads the outline (symbol tree) for the active document from its LSP.
    /// No-op for languages without a server; clears for non-file buffers.
    func refreshOutline() {
        outlineTask?.cancel()
        guard let doc = activeTab?.document, let url = doc.fileURL,
              LSPService.config(for: doc.language) != nil else {
            outlineSymbols = []
            isLoadingOutline = false
            return
        }
        isLoadingOutline = true
        let language = doc.language
        let uri = url.absoluteString
        let text = doc.text
        let root = rootURL?.path ?? url.deletingLastPathComponent().path
        outlineTask = Task { [weak self] in
            let symbols = await LSPService.shared.documentSymbols(language: language, uri: uri, text: text, root: root)
            guard let self, !Task.isCancelled else { return }
            self.outlineSymbols = symbols
            self.isLoadingOutline = false
        }
    }

    /// Resolves project references for a zero-based LSP position in the active
    /// document. Presentation and navigation stay with the caller.
    func findReferences(line: Int, character: Int) async throws -> [LSPLocation] {
        guard let document = activeTab?.document, let url = document.fileURL else {
            throw LSPService.FeatureError.requestFailed("Find References")
        }
        return try await LSPService.shared.references(
            language: document.language,
            uri: url.absoluteString,
            text: document.text,
            line: line,
            character: character,
            root: rootURL?.path ?? url.deletingLastPathComponent().path
        )
    }
}
