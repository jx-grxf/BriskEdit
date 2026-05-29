import SwiftUI

struct FileTreeView: View {
    let root: URL
    @Bindable var workspace: WorkspaceModel
    @State private var query: String = ""
    @State private var codeOnly: Bool = false
    @State private var searchResults: [FileNode] = []
    @State private var isSearching: Bool = false

    var body: some View {
        VStack(spacing: 0) {
            searchHeader
            Divider()
            if isSearchMode {
                SearchResultsList(results: searchResults, root: root, workspace: workspace, isSearching: isSearching)
            } else {
                List(selection: $workspace.selectedSidebarURL) {
                    FileTreeBranch(node: FileNode(url: root, isDirectory: true), depth: 0)
                        .environment(workspace)
                }
                .listStyle(.sidebar)
                .id(workspace.reloadToken)
                .dropDestination(for: URL.self) { urls, _ in
                    workspace.handleTreeDrop(urls, into: root)
                }
            }
        }
        .onChange(of: workspace.selectedSidebarURL) { _, url in
            guard let url else { return }
            let isDirectory = (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true
            guard !isDirectory else { return }
            Task { await workspace.openFile(at: url) }
        }
        .task(id: searchKey) {
            await runSearch()
        }
    }

    private var isSearchMode: Bool {
        codeOnly || !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var searchKey: String {
        "\(root.path)|\(query)|\(codeOnly)|\(workspace.showHiddenFiles)|\(workspace.reloadToken)"
    }

    private var searchHeader: some View {
        VStack(spacing: 8) {
            HStack(spacing: 6) {
                TextField("Search files or type .ext", text: $query)
                    .textFieldStyle(.roundedBorder)
                Button {
                    workspace.promptNewFile()
                } label: {
                    Image(systemName: "doc.badge.plus")
                }
                .buttonStyle(.borderless)
                .help("New file in current folder")
            }
            HStack {
                Toggle("Code only", isOn: $codeOnly)
                    .toggleStyle(.button)
                    .controlSize(.small)
                Toggle("Hidden", isOn: Bindable(workspace).showHiddenFiles)
                    .toggleStyle(.button)
                    .controlSize(.small)
                    .onChange(of: workspace.showHiddenFiles) { _, _ in workspace.refreshFileTree() }
                Button("Refresh", systemImage: "arrow.clockwise") {
                    workspace.refreshFileTree()
                }
                .buttonStyle(.borderless)
                .controlSize(.small)
                if isSearchMode {
                    Button("Clear", systemImage: "xmark.circle") {
                        query = ""
                        codeOnly = false
                    }
                    .buttonStyle(.borderless)
                    .controlSize(.small)
                }
                Spacer()
                if isSearchMode {
                    Text("\(searchResults.count) match\(searchResults.count == 1 ? "" : "es")")
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)
                }
            }
            .font(.caption)
        }
        .padding(10)
    }

    @MainActor
    private func runSearch() async {
        guard isSearchMode else {
            searchResults = []
            isSearching = false
            return
        }
        isSearching = true
        try? await Task.sleep(for: .milliseconds(220))
        guard !Task.isCancelled else { return }
        let rootURL = root
        let currentQuery = query
        let currentCodeOnly = codeOnly
        let includeHidden = workspace.showHiddenFiles
        let results = await Task.detached(priority: .userInitiated) {
            FileNode.search(in: rootURL, query: currentQuery, codeOnly: currentCodeOnly, includeHidden: includeHidden)
        }.value
        guard !Task.isCancelled, currentQuery == query, currentCodeOnly == codeOnly, includeHidden == workspace.showHiddenFiles else { return }
        searchResults = results
        isSearching = false
    }
}

private struct SearchResultsList: View {
    let results: [FileNode]
    let root: URL
    @Bindable var workspace: WorkspaceModel
    let isSearching: Bool

    var body: some View {
        List(selection: $workspace.selectedSidebarURL) {
            if isSearching && results.isEmpty {
                ProgressView()
                    .frame(maxWidth: .infinity, alignment: .center)
            }
            ForEach(results) { node in
                Button {
                    workspace.selectedSidebarURL = node.url
                } label: {
                    FileResultRow(node: node, root: root)
                }
                .buttonStyle(.plain)
                .tag(node.url)
                .contextMenu { FileContextMenu(node: node, workspace: workspace) }
            }
        }
        .listStyle(.sidebar)
    }
}

private struct FileResultRow: View {
    let node: FileNode
    let root: URL

    var body: some View {
        HStack(spacing: 8) {
            FileTypeIcon(url: node.url, isDirectory: node.isDirectory, language: node.language)
                .frame(width: 18)
            VStack(alignment: .leading, spacing: 2) {
                Text(node.name)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Text(relativePath)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
        }
        .padding(.vertical, 2)
    }

    private var relativePath: String {
        let path = node.url.deletingLastPathComponent().path
        let prefix = root.path
        if path.hasPrefix(prefix) {
            let relative = path.dropFirst(prefix.count).trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            return relative.isEmpty ? root.lastPathComponent : String(relative)
        }
        return path
    }
}

private struct FileTreeBranch: View {
    let node: FileNode
    let depth: Int
    @Environment(WorkspaceModel.self) private var workspace
    @State private var children: [FileNode] = []
    @State private var didLoad: Bool = false

    init(node: FileNode, depth: Int) {
        self.node = node
        self.depth = depth
    }

    /// Expansion state lives in the model so reloads don't collapse the tree.
    private var isExpanded: Binding<Bool> {
        Binding(
            get: { depth == 0 || workspace.expandedDirectories.contains(node.url) },
            set: { expand in
                if expand { workspace.expandedDirectories.insert(node.url) }
                else { workspace.expandedDirectories.remove(node.url) }
            }
        )
    }

    var body: some View {
        if node.isDirectory {
            DisclosureGroup(isExpanded: isExpanded) {
                ForEach(children) { child in
                    FileTreeBranch(node: child, depth: depth + 1)
                        .environment(workspace)
                }
            } label: {
                FileTreeRow(node: node, isExpanded: isExpanded.wrappedValue)
                    .contextMenu { FileContextMenu(node: node, workspace: workspace) }
                    .draggable(node.url)
                    .dropDestination(for: URL.self) { urls, _ in
                        workspace.handleTreeDrop(urls, into: node.url)
                    }
            }
            .tag(node.url)
            .task(id: "\(node.id.path)|\(workspace.reloadToken)|\(workspace.showHiddenFiles)") {
                if isExpanded.wrappedValue {
                    await loadChildren(force: true)
                }
            }
            .onChange(of: isExpanded.wrappedValue) { _, expanded in
                guard expanded else { return }
                Task { await loadChildren(force: false) }
            }
        } else {
            FileTreeRow(node: node, isExpanded: false)
            .tag(node.url)
            .contextMenu { FileContextMenu(node: node, workspace: workspace) }
            .draggable(node.url)
        }
    }

    @MainActor
    private func loadChildren(force: Bool) async {
        guard force || !didLoad else { return }
        let loaded = await workspace.loadChildren(of: node.url)
        children = loaded
        didLoad = true
    }
}

private struct FileTreeRow: View {
    let node: FileNode
    let isExpanded: Bool

    var body: some View {
        HStack(spacing: 8) {
            FileTypeIcon(url: node.url, isDirectory: node.isDirectory, language: node.language)
                .frame(width: 18)
            Text(node.name.isEmpty ? node.url.path : node.name)
                .foregroundStyle(.primary)
                .lineLimit(1)
                .truncationMode(.middle)
        }
        .help(node.url.path)
    }
}

private struct FileContextMenu: View {
    let node: FileNode
    let workspace: WorkspaceModel

    var body: some View {
        if node.isDirectory {
            Button("New File…") { workspace.promptNewFile(in: node.url) }
            Divider()
        } else {
            Button("Open") { workspace.selectedSidebarURL = node.url }
            if node.url.pathExtension.lowercased() == "pdf" {
                Button("Open in Split Screen") { workspace.toggleSplitPDF(node.url) }
            }
            Divider()
        }
        Button("Reveal in Finder") { workspace.revealInFinder(node.url) }
        Button("Copy Path") { workspace.copyToPasteboard(node.url.path) }
        Button("Copy Relative Path") { workspace.copyToPasteboard(workspace.relativePath(of: node.url)) }
        Button("Copy Name") { workspace.copyToPasteboard(node.name) }
        Divider()
        Button("Rename…") { workspace.renameFile(node.url) }
        Button("Duplicate") { workspace.duplicateFile(node.url) }
        Divider()
        Button("Move to Trash", role: .destructive) { workspace.deleteFile(node.url) }
    }
}

