import AppKit
import SwiftUI

struct FileTreeView: View {
    let root: URL
    @Bindable var workspace: WorkspaceModel
    @State private var query: String = ""
    @State private var codeOnly: Bool = false
    @State private var searchResults: [FileNode] = []
    @State private var isSearching: Bool = false
    @State private var isRootDropTargeted: Bool = false

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
                .dropDestination(for: URL.self) { urls, _ in
                    workspace.handleTreeDrop(urls, into: root)
                } isTargeted: { targeted in
                    withAnimation(.easeOut(duration: 0.12)) { isRootDropTargeted = targeted }
                }
                .overlay(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .strokeBorder(Color.accentColor.opacity(isRootDropTargeted ? 0.7 : 0), lineWidth: 2)
                        .padding(2)
                        .allowsHitTesting(false)
                )
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
        // File-tree git badges: refresh on root/file-op changes, after git
        // operations elsewhere, and when the window re-activates (so a save or
        // commit in another app is reflected).
        .task(id: "\(root.path)|\(workspace.reloadToken)") {
            await workspace.refreshGitDecorations()
        }
        .onReceive(NotificationCenter.default.publisher(for: .gitDidChange)) { _ in
            Task { await workspace.refreshGitDecorations() }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didBecomeKeyNotification)) { _ in
            Task { await workspace.refreshGitDecorations() }
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
                .help("New file in selected folder (or root)")
                Button {
                    workspace.promptNewFolder()
                } label: {
                    Image(systemName: "folder.badge.plus")
                }
                .buttonStyle(.borderless)
                .help("New folder in selected folder (or root)")
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
    @State private var isDropTargeted: Bool = false
    @State private var springLoadTask: Task<Void, Never>?

    init(node: FileNode, depth: Int) {
        self.node = node
        self.depth = depth
    }

    /// Reloads this branch's children when the whole tree refreshes
    /// (`reloadToken`), when *this* folder is individually refreshed (its
    /// per-directory token), or when the hidden-files toggle changes. Keying the
    /// task on the per-directory token means creating a file elsewhere no longer
    /// reloads — and scroll-resets — this branch.
    private var branchReloadKey: String {
        let dirToken = workspace.directoryRefreshTokens[node.url.standardizedFileURL]?.uuidString ?? ""
        return "\(node.id.path)|\(workspace.reloadToken)|\(dirToken)|\(workspace.showHiddenFiles)"
    }

    /// Expansion state lives in the model so reloads don't collapse the tree.
    /// The root folder is seeded into `expandedDirectories` when a workspace
    /// opens, so it starts expanded but — unlike before — can also be collapsed.
    private var isExpanded: Binding<Bool> {
        Binding(
            get: { workspace.expandedDirectories.contains(node.url) },
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
                FileTreeRow(node: node, isExpanded: isExpanded.wrappedValue, isDropTarget: isDropTargeted)
                    .contextMenu { FileContextMenu(node: node, workspace: workspace) }
                    .draggable(node.url) { FileDragPreview(node: node) }
                    .dropDestination(for: URL.self) { urls, _ in
                        workspace.handleTreeDrop(urls, into: node.url)
                    } isTargeted: { targeted in
                        handleDropTargetChange(targeted)
                    }
            }
            .tag(node.url)
            .task(id: branchReloadKey) {
                if isExpanded.wrappedValue {
                    await loadChildren(force: true)
                } else {
                    // A refresh token bumped while collapsed: invalidate so the
                    // next expand reloads fresh instead of showing stale children.
                    didLoad = false
                }
            }
            .onChange(of: isExpanded.wrappedValue) { _, expanded in
                guard expanded else { return }
                Task { await loadChildren(force: false) }
            }
        } else {
            FileTreeRow(node: node, isExpanded: false, isDropTarget: false)
            .tag(node.url)
            .contextMenu { FileContextMenu(node: node, workspace: workspace) }
            .draggable(node.url) { FileDragPreview(node: node) }
        }
    }

    /// Highlights the folder while a drag hovers it and arms a "spring-loaded"
    /// auto-expand so the user can drill into a collapsed folder mid-drag.
    private func handleDropTargetChange(_ targeted: Bool) {
        withAnimation(.easeOut(duration: 0.12)) { isDropTargeted = targeted }
        springLoadTask?.cancel()
        guard targeted, !isExpanded.wrappedValue else { return }
        springLoadTask = Task {
            try? await Task.sleep(for: .milliseconds(550))
            guard !Task.isCancelled, isDropTargeted else { return }
            withAnimation { isExpanded.wrappedValue = true }
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
    var isDropTarget: Bool = false
    @Environment(WorkspaceModel.self) private var workspace

    /// Git status for this exact file, if any.
    private var decoration: GitDecoration? {
        workspace.gitDecorations.files[node.url.standardizedFileURL]
    }

    /// A collapsed/expanded folder that contains changes somewhere below it.
    private var folderHasChanges: Bool {
        node.isDirectory && decoration == nil
            && workspace.gitDecorations.dirtyDirectories.contains(node.url.standardizedFileURL)
    }

    private var nameColor: Color {
        decoration?.tint ?? .primary
    }

    var body: some View {
        HStack(spacing: 8) {
            FileTypeIcon(url: node.url, isDirectory: node.isDirectory, language: node.language)
                .frame(width: 18)
            Text(node.name.isEmpty ? node.url.path : node.name)
                .foregroundStyle(nameColor)
                .lineLimit(1)
                .truncationMode(.middle)
            Spacer(minLength: 0)
            if let decoration {
                Text(decoration.badge)
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .foregroundStyle(decoration.tint)
                    .accessibilityLabel("Git status \(decoration.rawValue)")
            } else if folderHasChanges {
                Circle()
                    .fill(Color.orange.opacity(0.8))
                    .frame(width: 5, height: 5)
                    .accessibilityLabel("Contains changes")
            }
        }
        .padding(.vertical, 2)
        .padding(.horizontal, 4)
        .contentShape(Rectangle())
        .background(
            RoundedRectangle(cornerRadius: 5, style: .continuous)
                .fill(Color.accentColor.opacity(isDropTarget ? 0.18 : 0))
                .overlay(
                    RoundedRectangle(cornerRadius: 5, style: .continuous)
                        .strokeBorder(Color.accentColor.opacity(isDropTarget ? 0.7 : 0), lineWidth: 1)
                )
        )
        .help(node.url.path)
    }
}

/// Compact drag preview shown under the cursor while dragging a tree entry,
/// using the same icon as the row for visual continuity.
private struct FileDragPreview: View {
    let node: FileNode

    var body: some View {
        HStack(spacing: 6) {
            FileTypeIcon(url: node.url, isDirectory: node.isDirectory, language: node.language)
                .frame(width: 16)
            Text(node.name.isEmpty ? node.url.path : node.name)
                .lineLimit(1)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
    }
}

private struct FileContextMenu: View {
    let node: FileNode
    let workspace: WorkspaceModel

    var body: some View {
        if node.isDirectory {
            Button("New File…") { workspace.promptNewFile(in: node.url) }
            Button("New Folder…") { workspace.promptNewFolder(in: node.url) }
            Divider()
        } else {
            Button("Open") { workspace.selectedSidebarURL = node.url }
            if SplitPreviewContent.supports(node.url) {
                Button("Open in Split Screen") {
                    Task { await workspace.openInSplitScreen(node.url) }
                }
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

extension GitDecoration {
    /// Tint used for the row's filename and its trailing status badge.
    var tint: Color {
        switch self {
        case .modified: .orange
        case .added, .untracked: .green
        case .renamed: .blue
        case .conflicted, .deleted: .red
        }
    }
}
