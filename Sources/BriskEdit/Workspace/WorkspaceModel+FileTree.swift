import Foundation

// Workspace root, file-tree reloading and lazy child loading.
extension WorkspaceModel {
    func setWorkspaceRoot(_ url: URL) {
        rootURL = url
        RecentWorkspacesStore.shared.record(url)
        selectedSidebarURL = nil
        expandedDirectories = [url]
        childCache.removeAll(keepingCapacity: true)
        reloadToken = UUID()
        // Opening a folder reveals the integrated terminal at the workspace root
        // by default; an existing session is relocated, otherwise the panel
        // spins one up on appear.
        showTerminal = true
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
        splitPreviewContent = nil
        reloadToken = UUID()
        if persistsSession {
            UserDefaults.standard.removeObject(forKey: Keys.lastWorkspaceRoot)
        }
    }

    func refreshFileTree() {
        childCache.removeAll(keepingCapacity: true)
        reloadToken = UUID()
    }

    /// Reloads a single folder's children in the file tree (after a create /
    /// delete / rename in that folder) without touching the rest of the tree, so
    /// the scroll position is kept. Pass the *directory* whose contents changed.
    func refreshDirectory(_ url: URL) {
        let dir = url.standardizedFileURL
        childCache = childCache.filter { $0.key.url.standardizedFileURL != dir }
        directoryRefreshTokens[dir] = UUID()
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

    /// Reveals a path in the file tree: switches to the Files pane, expands every
    /// ancestor folder (and the target itself if it is a directory) and selects
    /// it. Used by the breadcrumb bar's path segments.
    func revealInFileTree(_ url: URL, isDirectory: Bool) {
        guard let root = rootURL else { return }
        sidebarTab = .files
        let rootStd = root.standardizedFileURL
        expandedDirectories.insert(rootStd)
        if isDirectory { expandedDirectories.insert(url.standardizedFileURL) }
        var dir = url.deletingLastPathComponent().standardizedFileURL
        while dir.path.hasPrefix(rootStd.path) {
            expandedDirectories.insert(dir)
            if dir.path == rootStd.path { break }
            let parent = dir.deletingLastPathComponent().standardizedFileURL
            if parent.path == dir.path { break }
            dir = parent
        }
        selectedSidebarURL = url
    }

    /// Recomputes the file-tree git badges for the current workspace root.
    func refreshGitDecorations() async {
        guard let root = rootURL else {
            if !gitDecorations.isEmpty { gitDecorations = GitDecorations() }
            return
        }
        gitDecorations = await GitService.decorations(root: root)
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
}
