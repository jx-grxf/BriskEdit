import Foundation

/// Reads the checked-out branch straight out of `.git/HEAD`.
///
/// The welcome screen labels a handful of recent folders at launch. Asking
/// `GitService.status` would spawn a `git` process per folder before the user
/// has done anything; HEAD is a single small file and answers the same question.
enum GitHeadProbe {
    /// Branch per folder, for those that are repositories. Runs off the main
    /// actor: a stale network mount must not stall the first frame.
    static func branches(for folders: [URL]) async -> [URL: String] {
        guard !folders.isEmpty else { return [:] }
        return await Task.detached(priority: .utility) {
            var result: [URL: String] = [:]
            for folder in folders {
                if let branch = branch(at: folder) { result[folder] = branch }
            }
            return result
        }.value
    }

    /// nil when the folder is not a repository, or HEAD is unreadable.
    static func branch(at folder: URL) -> String? {
        guard let head = headURL(for: folder),
              let contents = try? String(contentsOf: head, encoding: .utf8) else { return nil }
        return branchName(fromHEAD: contents)
    }

    /// `.git` is a directory in a normal clone and a `gitdir:` pointer file in a
    /// worktree or submodule; HEAD lives next to the real git directory.
    private static func headURL(for folder: URL) -> URL? {
        let dotGit = folder.appendingPathComponent(".git")
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: dotGit.path, isDirectory: &isDirectory) else { return nil }
        if isDirectory.boolValue { return dotGit.appendingPathComponent("HEAD") }
        guard let pointer = try? String(contentsOf: dotGit, encoding: .utf8),
              let path = gitDirectory(fromPointer: pointer) else { return nil }
        let directory = path.hasPrefix("/")
            ? URL(fileURLWithPath: path)
            : folder.appendingPathComponent(path).standardizedFileURL
        return directory.appendingPathComponent("HEAD")
    }

    /// `ref: refs/heads/topic` → `topic`. A detached HEAD keeps its short commit,
    /// which is what the user needs to recognize the checkout; anything else
    /// (a tag ref, an empty file) has no branch to show.
    static func branchName(fromHEAD contents: String) -> String? {
        let line = contents.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !line.isEmpty else { return nil }
        if line.hasPrefix("ref:") {
            let reference = line.dropFirst("ref:".count).trimmingCharacters(in: .whitespaces)
            guard reference.hasPrefix("refs/heads/") else { return nil }
            let name = String(reference.dropFirst("refs/heads/".count))
            return name.isEmpty ? nil : name
        }
        guard line.count >= 7, line.allSatisfy(\.isHexDigit) else { return nil }
        return String(line.prefix(7))
    }

    /// The path a `.git` pointer file points at; relative paths stay relative so
    /// the caller can resolve them against the worktree.
    static func gitDirectory(fromPointer contents: String) -> String? {
        for line in contents.split(separator: "\n") where line.hasPrefix("gitdir:") {
            let path = line.dropFirst("gitdir:".count).trimmingCharacters(in: .whitespaces)
            return path.isEmpty ? nil : path
        }
        return nil
    }
}
