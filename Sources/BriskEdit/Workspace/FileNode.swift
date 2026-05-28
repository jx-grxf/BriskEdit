import Foundation

struct FileNode: Identifiable, Hashable, Sendable {
    let url: URL
    let isDirectory: Bool

    var id: URL { url }
    var name: String { url.lastPathComponent }
    var language: SourceLanguage { SourceLanguage(url: url, displayName: name) }
    var isCodeFile: Bool {
        switch language {
        case .c, .cpp, .css, .go, .html, .javascript, .json, .markdown, .python, .rust, .shell, .swift, .typescript, .yaml:
            true
        case .plainText:
            false
        }
    }

    static func children(of url: URL, includeHidden: Bool = false) -> [FileNode] {
        let fm = FileManager.default
        guard let entries = try? fm.contentsOfDirectory(
            at: url,
            includingPropertiesForKeys: [.isDirectoryKey, .isHiddenKey],
            options: includeHidden ? [.skipsPackageDescendants] : [.skipsHiddenFiles, .skipsPackageDescendants]
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
            options: includeHidden ? [.skipsPackageDescendants] : [.skipsHiddenFiles, .skipsPackageDescendants]
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
        if alwaysHiddenDirectoryNames.contains(name) { return true }
        if !includeHidden, name.hasPrefix(".") { return true }
        if hiddenDirectoryNames.contains(name) { return true }
        for suffix in hiddenSuffixes where name.hasSuffix(suffix) { return true }
        return false
    }

    private static let alwaysHiddenDirectoryNames: Set<String> = [
        ".git", ".svn", ".hg", ".build"
    ]

    private static let hiddenDirectoryNames: Set<String> = [
        "build", "dist", "out", "bin", "obj",
        "DerivedData", "Pods", "Carthage",
        "node_modules", "bower_components",
        "__pycache__", "venv", "env",
        "target", "vendor", "coverage", "tmp", "temp"
    ]

    private static let hiddenSuffixes: [String] = [
        ".dSYM", ".xcuserdatad", ".xcuserstate",
        ".o", ".obj", ".a", ".lib",
        ".pyc", ".class",
        ".log", ".DS_Store"
    ]
}
