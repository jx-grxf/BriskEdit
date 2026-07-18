import SwiftUI

/// Flat, ignore-aware enumeration of files under a root, shared by the
/// go-to-file palette. Honors the same skip rules as the file tree.
enum FileIndex {
    static func files(under root: URL, includeHidden: Bool, limit: Int) -> [URL] {
        let fm = FileManager.default
        guard let enumerator = fm.enumerator(
            at: root,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: includeHidden ? [.skipsPackageDescendants] : [.skipsHiddenFiles, .skipsPackageDescendants]
        ) else { return [] }

        var results: [URL] = []
        for case let url as URL in enumerator {
            let isDir = (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true
            if FileNode.shouldHide(url: url, includeHidden: includeHidden) {
                if isDir { enumerator.skipDescendants() }
                continue
            }
            if isDir { continue }
            results.append(url)
            if results.count >= limit { break }
        }
        return results
    }
}

/// Subsequence fuzzy matcher with light scoring: rewards consecutive matches and
/// matches at word/segment boundaries, so "wm" ranks `WorkspaceModel.swift`
/// above `framework.swift`. Returns nil when `query` is not a subsequence.
enum FuzzyMatch {
    static func score(query: [Character], candidate: String) -> Int? {
        guard !query.isEmpty else { return 0 }
        let chars = Array(candidate.lowercased())
        var qi = 0
        var score = 0
        var lastMatch = -2
        var prevChar: Character = "/"
        for (ci, ch) in chars.enumerated() where qi < query.count {
            if ch == query[qi] {
                var bonus = 1
                if ci == lastMatch + 1 { bonus += 5 }                       // consecutive
                if prevChar == "/" || prevChar == "_" || prevChar == "." || prevChar == "-" { bonus += 8 } // segment start
                score += bonus
                lastMatch = ci
                qi += 1
            }
            prevChar = ch
        }
        return qi == query.count ? score : nil
    }
}

/// ⌘P-style palette that fuzzy-matches files in the workspace and opens the
/// chosen one in a tab.
struct FileFinderView: View {
    @Bindable var workspace: WorkspaceModel
    @State private var query: String = ""
    @State private var allFiles: [URL] = []
    @State private var displayedResults: [URL] = []
    @State private var selection: URL?
    @State private var searchTask: Task<Void, Never>?
    @FocusState private var fieldFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            TextField("Go to file", text: $query)
                .textFieldStyle(.plain)
                .font(.system(size: 16))
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .focused($fieldFocused)
                .onSubmit { openSelection() }
            Divider()
            List(selection: $selection) {
                ForEach(displayedResults, id: \.self) { url in
                    Button {
                        selection = url
                        openSelection()
                    } label: {
                        HStack(spacing: 8) {
                            FileTypeIcon(url: url, isDirectory: false,
                                         language: FileNode(url: url, isDirectory: false).language,
                                         size: 16)
                                .frame(width: 18)
                            Text(url.lastPathComponent)
                            Spacer()
                            Text(workspace.relativePath(of: url.deletingLastPathComponent()))
                                .foregroundStyle(.secondary)
                                .font(.caption)
                                .lineLimit(1)
                                .truncationMode(.head)
                        }
                    }
                    .buttonStyle(.plain)
                    .tag(url)
                }
            }
            .listStyle(.plain)
            .frame(minHeight: 320)
        }
        .frame(width: 560)
        .task {
            allFiles = await workspace.collectWorkspaceFiles()
            updateResults()
            fieldFocused = true
        }
        .onChange(of: query) { _, _ in updateResults() }
        .onChange(of: allFiles) { _, _ in updateResults() }
        .onDisappear {
            searchTask?.cancel()
        }
        .onExitCommand { workspace.showFileFinder = false }
    }

    private func openSelection() {
        guard let url = selection ?? displayedResults.first else { return }
        workspace.showFileFinder = false
        Task { await workspace.openFile(at: url) }
    }

    private func updateResults() {
        searchTask?.cancel()
        let querySnapshot = query
        let candidates = allFiles.map { url in
            FileSearchCandidate(
                url: url,
                name: url.lastPathComponent,
                relativePath: workspace.relativePath(of: url)
            )
        }
        searchTask = Task {
            let matches = await Task.detached(priority: .userInitiated) {
                FileSearch.search(query: querySnapshot, candidates: candidates)
            }.value
            guard !Task.isCancelled else { return }
            displayedResults = matches
            selection = matches.first
        }
    }
}

private struct FileSearchCandidate: Sendable {
    let url: URL
    let name: String
    let relativePath: String
}

private enum FileSearch {
    static func search(query: String, candidates: [FileSearchCandidate]) -> [URL] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !trimmed.isEmpty else {
            return Array(candidates.prefix(200).map(\.url))
        }
        let q = Array(trimmed.filter { !$0.isWhitespace })
        return candidates
            .compactMap { candidate -> (URL, Int)? in
                let nameScore = FuzzyMatch.score(query: q, candidate: candidate.name).map { $0 + 12 }
                let pathScore = FuzzyMatch.score(query: q, candidate: candidate.relativePath)
                guard let best = [nameScore, pathScore].compactMap({ $0 }).max() else { return nil }
                return (candidate.url, best)
            }
            .sorted { $0.1 > $1.1 }
            .prefix(200)
            .map(\.0)
    }
}
