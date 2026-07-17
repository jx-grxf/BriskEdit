import Foundation

struct FileNode: Identifiable, Hashable, Sendable {
    let url: URL
    let isDirectory: Bool

    var id: URL { url }
    var name: String { url.lastPathComponent }
    var language: SourceLanguage { SourceLanguage(url: url, displayName: name) }
    var isCodeFile: Bool {
        language != .plainText
    }

    static func children(of url: URL, includeHidden: Bool = false) -> [FileNode] {
        let fm = FileManager.default
        // Never pass `.skipsHiddenFiles`: it drops every dotfile at the
        // FileManager layer before `shouldHide` can decide. We want meaningful
        // dotfiles (.github, .gitignore, …) visible by default — `shouldHide`
        // does the filtering instead.
        guard let entries = try? fm.contentsOfDirectory(
            at: url,
            includingPropertiesForKeys: [.isDirectoryKey, .isHiddenKey],
            options: [.skipsPackageDescendants]
        ) else {
            return []
        }
        return entries
            .filter { !shouldHide(url: $0, includeHidden: includeHidden) }
            .map { entry -> FileNode in
                let values = try? entry.resourceValues(forKeys: [.isDirectoryKey])
                return FileNode(url: entry, isDirectory: values?.isDirectory ?? false)
            }
            .sorted { lhs, rhs in
                if lhs.isDirectory != rhs.isDirectory { return lhs.isDirectory && !rhs.isDirectory }
                return lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
            }
    }

    static func search(in root: URL, query: String, codeOnly: Bool, includeHidden: Bool = false, limit: Int = 300) -> [FileNode] {
        let trimmedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let fm = FileManager.default
        guard let enumerator = fm.enumerator(
            at: root,
            includingPropertiesForKeys: [.isDirectoryKey, .isHiddenKey],
            options: [.skipsPackageDescendants]
        ) else {
            return []
        }

        var matches: [FileNode] = []
        for case let url as URL in enumerator {
            let name = url.lastPathComponent
            let isDir = (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true
            if shouldHide(url: url, includeHidden: includeHidden) {
                if isDir { enumerator.skipDescendants() }
                continue
            }

            let node = FileNode(url: url, isDirectory: isDir)
            guard !node.isDirectory else { continue }
            if codeOnly, !node.isCodeFile { continue }
            if !trimmedQuery.isEmpty {
                let lowerName = name.lowercased()
                let relative = url.path.replacingOccurrences(of: root.path, with: "").lowercased()
                if trimmedQuery.hasPrefix(".") {
                    // Treat ".c", ".swift" etc. as strict extension filters so
                    // ".c" doesn't match ".css" or ".cpp".
                    guard lowerName.hasSuffix(trimmedQuery) else { continue }
                } else {
                    guard lowerName.contains(trimmedQuery) || relative.contains(trimmedQuery) else {
                        continue
                    }
                }
            }
            matches.append(node)
            if matches.count >= limit { break }
        }
        return matches.sorted { lhs, rhs in
            lhs.url.path.localizedStandardCompare(rhs.url.path) == .orderedAscending
        }
    }

    static func shouldHide(url: URL, includeHidden: Bool = false) -> Bool {
        let name = url.lastPathComponent
        // VCS metadata and OS noise stay hidden even with "Hidden" on — they
        // are never useful to browse. Mirrors VS Code's default `files.exclude`.
        if alwaysHiddenNames.contains(name) { return true }
        // "Hidden" toggle = show everything else: dotfiles *and* heavy build /
        // dependency output (.build, build, dist, node_modules, …), mirroring
        // git-ignored entries are commonly surfaced (greyed).
        if includeHidden { return false }
        // Default view: keep meaningful dotfiles (.github, .gitignore, …) but
        // suppress generated / dependency directories and build noise.
        if hiddenDirectoryNames.contains(name) { return true }
        // `bin` / `obj` are .NET build output — but in Node (CLI entry point),
        // Go, Rails, and shell projects `bin/` is hand-authored *source*. Only
        // hide them when a sibling .NET project/solution proves they're generated.
        if contextHiddenDirectoryNames.contains(name), isDotNetBuildOutput(url) { return true }
        for suffix in hiddenSuffixes where name.hasSuffix(suffix) { return true }
        return false
    }

    private static let alwaysHiddenNames: Set<String> = [
        ".git", ".svn", ".hg", "CVS", ".DS_Store", "Thumbs.db"
    ]

    private static let hiddenDirectoryNames: Set<String> = [
        ".build", "build", "dist", "out",
        "DerivedData", "Pods", "Carthage",
        "node_modules", "bower_components",
        "__pycache__", ".venv", "venv", "env",
        ".tox", ".next", ".turbo",
        "target", "vendor", "coverage", "tmp", "temp"
    ]

    // Names that are ambiguous: build output in one ecosystem, hand-authored
    // source in another. Hidden only when `isDotNetBuildOutput` confirms they
    // are generated — never blanket-hidden, so we don't bury source.
    private static let contextHiddenDirectoryNames: Set<String> = ["bin", "obj"]

    private static let dotNetProjectSuffixes = [".sln", ".csproj", ".fsproj", ".vbproj"]

    /// `bin`/`obj` are .NET build artifacts only when a sibling project or
    /// solution file is present. Elsewhere (npm `bin`, Rails `bin`, Go) they
    /// hold source we must keep visible.
    private static func isDotNetBuildOutput(_ url: URL) -> Bool {
        let parent = url.deletingLastPathComponent()
        guard let siblings = try? FileManager.default.contentsOfDirectory(
            at: parent,
            includingPropertiesForKeys: nil,
            options: []
        ) else {
            return false
        }
        return siblings.contains { sibling in
            let last = sibling.lastPathComponent
            return dotNetProjectSuffixes.contains { last.hasSuffix($0) }
        }
    }

    private static let hiddenSuffixes: [String] = [
        ".dSYM", ".xcuserdatad", ".xcuserstate",
        ".o", ".obj", ".a", ".lib",
        ".pyc", ".class",
        ".log", ".DS_Store"
    ]
}
