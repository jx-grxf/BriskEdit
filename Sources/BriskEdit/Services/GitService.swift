import Foundation

enum GitChangeKind: Sendable {
    case added
    case modified
}

/// Per-line VCS status for a single file, mapped to 1-based buffer line numbers.
struct GitDiff: Sendable {
    var lineKinds: [Int: GitChangeKind] = [:]
    /// Buffer lines that have a deletion immediately above them (drawn as a
    /// small triangle in the gutter).
    var deletions: Set<Int> = []

    var isEmpty: Bool { lineKinds.isEmpty && deletions.isEmpty }
}

/// One changed file in `git status`, split per stage so a file with both staged
/// and unstaged edits appears in both sections.
struct GitFileChange: Sendable, Identifiable, Hashable {
    let path: String        // repo-relative
    let staged: Bool
    let status: String      // porcelain code: M, A, D, R, ?, …

    var id: String { (staged ? "S:" : "U:") + path }
    var displayName: String { (path as NSString).lastPathComponent }
    var directory: String { (path as NSString).deletingLastPathComponent }
}

/// Snapshot of the working tree's VCS state for the Source Control sidebar.
struct GitStatus: Sendable {
    var branch: String?
    var upstream: String?
    var ahead: Int = 0
    var behind: Int = 0
    var hasRemote: Bool = false
    var changes: [GitFileChange]

    var staged: [GitFileChange] { changes.filter(\.staged) }
    var unstaged: [GitFileChange] { changes.filter { !$0.staged } }
    var isClean: Bool { changes.isEmpty }
}

/// One entry in the recent-commit history shown in the Source Control pane.
struct GitCommit: Sendable, Identifiable, Hashable {
    let hash: String
    let shortHash: String
    let subject: String
    let author: String
    /// Human "2 hours ago" string from `git log %cr`.
    let relativeDate: String
    /// Not yet on the upstream branch (ahead of `@{u}`, or no upstream at all).
    let isUnpushed: Bool

    var id: String { hash }
}

/// Outcome of a git command that can fail in a way worth surfacing (push, pull,
/// checkout). `output` carries the combined stdout+stderr for the error banner.
struct GitResult: Sendable {
    let ok: Bool
    let output: String
}

/// VCS status of a single file, used to decorate file-tree rows.
enum GitDecoration: String, Sendable {
    case modified, added, untracked, deleted, renamed, conflicted

    /// Single-letter badge shown at the trailing edge of a tree row.
    var badge: String {
        switch self {
        case .modified: "M"
        case .added: "A"
        case .untracked: "U"
        case .deleted: "D"
        case .renamed: "R"
        case .conflicted: "!"
        }
    }
}

/// File-tree decoration snapshot: the per-file status plus the set of folders
/// that contain at least one changed descendant (so collapsed folders can still
/// signal "something changed in here").
struct GitDecorations: Sendable {
    var files: [URL: GitDecoration] = [:]
    var dirtyDirectories: Set<URL> = []

    var isEmpty: Bool { files.isEmpty }
}

/// Author/commit info for a single buffer line, for inline blame.
struct GitBlame: Sendable, Equatable {
    let author: String
    let summary: String
    let timestamp: Date
    let isUncommitted: Bool

    /// "Johannes Grof · 3 days ago" style label (uncommitted lines read
    /// "You · Uncommitted").
    var label: String {
        if isUncommitted { return "You · Uncommitted" }
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .full
        let when = formatter.localizedString(for: timestamp, relativeTo: Date())
        let who = author.isEmpty ? "Unknown" : author
        return "\(who) · \(when)"
    }

    /// Full label including the commit summary, for the trailing ghost text.
    var detailedLabel: String {
        guard !isUncommitted, !summary.isEmpty else { return label }
        return "\(label) · \(summary)"
    }
}

/// Computes a git "gutter" diff by comparing the *current buffer* against the
/// committed `HEAD` blob — so it reflects uncommitted edits live, not just what
/// is saved. Shells out to the user's own `git`; returns nil outside a repo.
enum GitService {
    struct PorcelainEntry: Equatable {
        let index: Character
        let worktree: Character
        let path: String
    }

    /// Working-tree status (branch + changed files) for the Source Control view.
    /// Returns nil when the folder isn't inside a git repository.
    static func status(root: URL) async -> GitStatus? {
        let rootPath = root.path
        return await Task.detached(priority: .utility) { () -> GitStatus? in
            guard let top = run(["-C", rootPath, "rev-parse", "--show-toplevel"])?
                .trimmingCharacters(in: .whitespacesAndNewlines), !top.isEmpty else { return nil }
            let branch = run(["-C", top, "rev-parse", "--abbrev-ref", "HEAD"])?
                .trimmingCharacters(in: .whitespacesAndNewlines)
            let upstream = run(["-C", top, "rev-parse", "--abbrev-ref", "--symbolic-full-name", "@{u}"])?
                .trimmingCharacters(in: .whitespacesAndNewlines)
            var ahead = 0, behind = 0
            if let upstream, !upstream.isEmpty,
               let counts = run(["-C", top, "rev-list", "--count", "--left-right", "@{u}...HEAD"]) {
                let parts = counts.split(whereSeparator: { $0 == "\t" || $0 == " " })
                if parts.count == 2 { behind = Int(parts[0]) ?? 0; ahead = Int(parts[1]) ?? 0 }
            }
            let hasRemote = !((run(["-C", top, "remote"])?.trimmingCharacters(in: .whitespacesAndNewlines)) ?? "").isEmpty

            guard let data = runData(["-C", top, "status", "--porcelain=v1", "-z", "--untracked-files=all"]) else {
                return GitStatus(branch: branch, upstream: upstream, ahead: ahead, behind: behind, hasRemote: hasRemote, changes: [])
            }
            var changes: [GitFileChange] = []
            for entry in parsePorcelainV1Z(data) {
                let index = entry.index, worktree = entry.worktree, path = entry.path
                if index == "?" && worktree == "?" {
                    changes.append(GitFileChange(path: path, staged: false, status: "?"))
                } else {
                    if index != " " { changes.append(GitFileChange(path: path, staged: true, status: String(index))) }
                    if worktree != " " { changes.append(GitFileChange(path: path, staged: false, status: String(worktree))) }
                }
            }
            return GitStatus(branch: branch, upstream: upstream, ahead: ahead, behind: behind, hasRemote: hasRemote, changes: changes)
        }.value
    }

    /// Per-file decorations for the file tree (modified / added / untracked …),
    /// keyed by absolute, standardized URL, plus the set of ancestor folders that
    /// contain a change. Returns empty outside a repository.
    static func decorations(root: URL) async -> GitDecorations {
        let rootPath = root.path
        return await Task.detached(priority: .utility) { () -> GitDecorations in
            guard let top = run(["-C", rootPath, "rev-parse", "--show-toplevel"])?
                .trimmingCharacters(in: .whitespacesAndNewlines), !top.isEmpty,
                let data = runData(["-C", top, "status", "--porcelain=v1", "-z", "--untracked-files=all"]) else { return GitDecorations() }
            let topURL = URL(fileURLWithPath: top, isDirectory: true)
            let rootStd = URL(fileURLWithPath: rootPath, isDirectory: true).standardizedFileURL
            var result = GitDecorations()
            for entry in parsePorcelainV1Z(data) {
                let index = entry.index, worktree = entry.worktree, path = entry.path
                guard !path.isEmpty else { continue }
                let fileURL = topURL.appendingPathComponent(path).standardizedFileURL
                result.files[fileURL] = decoration(index: index, worktree: worktree)
                // Walk up to the workspace root marking each ancestor dirty.
                var dir = fileURL.deletingLastPathComponent().standardizedFileURL
                while dir.path.hasPrefix(rootStd.path) {
                    result.dirtyDirectories.insert(dir)
                    if dir.path == rootStd.path { break }
                    let parent = dir.deletingLastPathComponent().standardizedFileURL
                    if parent.path == dir.path { break }
                    dir = parent
                }
            }
            return result
        }.value
    }

    /// Blame for a single 1-based line of `file`, parsed from porcelain output.
    /// Returns nil outside a repo or on error. Uncommitted (locally edited but
    /// unstaged) lines come back with `isUncommitted == true`.
    static func blame(file: URL, line: Int, root: URL) async -> GitBlame? {
        guard line >= 1 else { return nil }
        let filePath = file.path
        let rootPath = root.path
        return await Task.detached(priority: .utility) { () -> GitBlame? in
            guard let out = run(["-C", rootPath, "blame", "-L", "\(line),\(line)", "--porcelain", "--", filePath]) else { return nil }
            var author = ""
            var summary = ""
            var authorTime: TimeInterval = 0
            var sha = ""
            var isFirst = true
            for raw in out.split(separator: "\n", omittingEmptySubsequences: false) {
                let lineStr = String(raw)
                if isFirst {
                    sha = String(lineStr.prefix(40))
                    isFirst = false
                    continue
                }
                if lineStr.hasPrefix("author ") {
                    author = String(lineStr.dropFirst("author ".count))
                } else if lineStr.hasPrefix("author-time ") {
                    authorTime = TimeInterval(lineStr.dropFirst("author-time ".count)) ?? 0
                } else if lineStr.hasPrefix("summary ") {
                    summary = String(lineStr.dropFirst("summary ".count))
                }
            }
            let uncommitted = author == "Not Committed Yet" || sha.allSatisfy { $0 == "0" }
            return GitBlame(
                author: author,
                summary: summary,
                timestamp: Date(timeIntervalSince1970: authorTime),
                isUncommitted: uncommitted
            )
        }.value
    }

    /// Maps a porcelain `XY` status pair to a single tree decoration. Conflicts
    /// (unmerged) win, then untracked, then the most relevant of the two stages.
    private static func decoration(index: Character, worktree: Character) -> GitDecoration {
        if index == "U" || worktree == "U"
            || (index == "A" && worktree == "A")
            || (index == "D" && worktree == "D") { return .conflicted }
        if index == "?" || worktree == "?" { return .untracked }
        let code = worktree != " " ? worktree : index
        switch code {
        case "A": return .added
        case "D": return .deleted
        case "R", "C": return .renamed
        default: return .modified
        }
    }

    /// Parses Git's NUL-delimited porcelain format. Unlike the line-oriented
    /// form, `-z` emits paths verbatim, so Unicode, quotes, tabs and newlines do
    /// not require Git's C-style unescaping. Rename entries include the old path
    /// as a second field; the first field is the destination path we display.
    static func parsePorcelainV1Z(_ data: Data) -> [PorcelainEntry] {
        let fields = data.split(separator: 0, omittingEmptySubsequences: true)
        var entries: [PorcelainEntry] = []
        var fieldIndex = 0
        while fieldIndex < fields.count {
            let field = fields[fieldIndex]
            guard field.count >= 4 else {
                fieldIndex += 1
                continue
            }
            let bytes = Array(field)
            let index = Character(UnicodeScalar(bytes[0]))
            let worktree = Character(UnicodeScalar(bytes[1]))
            let path = String(decoding: bytes.dropFirst(3), as: UTF8.self)
            entries.append(PorcelainEntry(index: index, worktree: worktree, path: path))

            fieldIndex += 1
            if index == "R" || index == "C" || worktree == "R" || worktree == "C" {
                fieldIndex += 1
            }
        }
        return entries
    }

    @discardableResult
    static func stage(_ path: String, root: URL) async -> GitResult {
        await runResult(["-C", root.path, "add", "--", path])
    }

    @discardableResult
    static func stageAll(root: URL) async -> GitResult {
        await runResult(["-C", root.path, "add", "-A"])
    }

    @discardableResult
    static func unstage(_ path: String, root: URL) async -> GitResult {
        await runResult(["-C", root.path, "restore", "--staged", "--", path])
    }

    /// Discards working-tree changes for a tracked file (destructive — the
    /// caller is expected to confirm first).
    @discardableResult
    static func discard(_ path: String, root: URL) async -> GitResult {
        await runResult(["-C", root.path, "restore", "--", path])
    }

    @discardableResult
    static func commit(message: String, root: URL) async -> GitResult {
        await runResult(["-C", root.path, "commit", "-m", message])
    }

    /// Pushes the current branch. If it has no upstream yet, retries with
    /// `-u origin HEAD` so the first push from a fresh branch just works.
    static func push(root: URL) async -> GitResult {
        let first = await runResult(["-C", root.path, "push"])
        if first.ok { return first }
        let lower = first.output.lowercased()
        if lower.contains("no upstream") || lower.contains("has no upstream") || lower.contains("set-upstream") {
            return await runResult(["-C", root.path, "push", "-u", "origin", "HEAD"])
        }
        return first
    }

    static func pull(root: URL) async -> GitResult {
        await runResult(["-C", root.path, "pull", "--ff-only"])
    }

    static func fetch(root: URL) async -> GitResult {
        await runResult(["-C", root.path, "fetch", "--prune"])
    }

    /// Local branches, current branch first.
    static func branches(root: URL) async -> [String] {
        await Task.detached(priority: .utility) {
            guard let out = run(["-C", root.path, "branch", "--format=%(refname:short)"]) else { return [] }
            return out.split(separator: "\n")
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .filter { !$0.isEmpty }
        }.value
    }

    /// Recent commits on the current branch, newest first, each flagged with
    /// whether it has been pushed to the upstream yet.
    static func recentCommits(root: URL, limit: Int = 30) async -> [GitCommit] {
        let rootPath = root.path
        return await Task.detached(priority: .utility) { () -> [GitCommit] in
            guard let top = run(["-C", rootPath, "rev-parse", "--show-toplevel"])?
                .trimmingCharacters(in: .whitespacesAndNewlines), !top.isEmpty else { return [] }

            // Hashes not yet on the upstream. With no upstream, every listed
            // commit counts as unpushed (the branch has never been pushed).
            var unpushed = Set<String>()
            let hasUpstream = !((run(["-C", top, "rev-parse", "--abbrev-ref", "--symbolic-full-name", "@{u}"], allowFailure: true) ?? "")
                .trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            if hasUpstream, let revs = run(["-C", top, "rev-list", "@{u}..HEAD"], allowFailure: true) {
                for line in revs.split(separator: "\n") { unpushed.insert(String(line)) }
            }

            // %x1f = unit separator between fields; one commit per line (%s is
            // already a single line).
            let format = "%H%x1f%h%x1f%s%x1f%an%x1f%cr"
            guard let out = run(["-C", top, "log", "-n", String(limit), "--pretty=format:\(format)"], allowFailure: true) else { return [] }
            var commits: [GitCommit] = []
            for line in out.split(separator: "\n") {
                let f = line.components(separatedBy: "\u{1f}")
                guard f.count == 5 else { continue }
                commits.append(GitCommit(
                    hash: f[0], shortHash: f[1], subject: f[2], author: f[3], relativeDate: f[4],
                    isUnpushed: !hasUpstream || unpushed.contains(f[0])
                ))
            }
            return commits
        }.value
    }

    static func checkout(_ branch: String, root: URL) async -> GitResult {
        await runResult(["-C", root.path, "checkout", branch])
    }

    static func createBranch(_ name: String, root: URL) async -> GitResult {
        await runResult(["-C", root.path, "checkout", "-b", name])
    }

    /// Runs git capturing stdout+stderr and the exit status — for operations
    /// whose failure the UI should surface.
    private static func runResult(_ args: [String]) async -> GitResult {
        await Task.detached(priority: .utility) { () -> GitResult in
            guard let result = BoundedProcessRunner.run(
                executableURL: URL(fileURLWithPath: "/usr/bin/env"),
                arguments: ["git"] + args,
                timeout: 5 * 60,
                maximumStandardOutputBytes: 8 * 1024 * 1024,
                maximumStandardErrorBytes: 8 * 1024 * 1024
            ) else {
                return GitResult(ok: false, output: "Could not start git.")
            }
            let combined = ((String(data: result.stdout, encoding: .utf8) ?? "") + (String(data: result.stderr, encoding: .utf8) ?? ""))
                .trimmingCharacters(in: .whitespacesAndNewlines)
            let suffix = result.timedOut ? "Git operation timed out." : (result.outputLimitExceeded ? "Git output exceeded the safety limit." : "")
            let output = [combined, suffix].filter { !$0.isEmpty }.joined(separator: "\n")
            return GitResult(ok: result.terminationStatus == 0 && !result.timedOut && !result.outputLimitExceeded, output: output)
        }.value
    }

    static func diff(for fileURL: URL, currentText: String) async -> GitDiff? {
        let path = fileURL.path
        let dir = fileURL.deletingLastPathComponent().path
        return await Task.detached(priority: .utility) { () -> GitDiff? in
            guard let root = run(["-C", dir, "rev-parse", "--show-toplevel"])?
                .trimmingCharacters(in: .whitespacesAndNewlines), !root.isEmpty else { return nil }
            guard path.hasPrefix(root + "/") else { return nil }
            let relative = String(path.dropFirst(root.count + 1))

            // HEAD version of the file. Missing → file is new/untracked; mark
            // every line as added only when Git already tracks it (staged add).
            // Ignored/untracked files intentionally get no gutter bar: there is
            // no committed baseline to compare against, so "all green" is noise.
            let head = run(["-C", root, "show", "HEAD:\(relative)"])
            guard let head else {
                guard run(["-C", root, "ls-files", "--error-unmatch", "--", relative]) != nil else {
                    return nil
                }
                var count = currentText.isEmpty ? 0 : currentText.components(separatedBy: "\n").count
                // A trailing newline doesn't start another line; without this
                // the last marked line would sit past EOF.
                if count > 0 && currentText.hasSuffix("\n") { count -= 1 }
                var diff = GitDiff()
                for line in 1...max(1, count) where count > 0 { diff.lineKinds[line] = .added }
                return diff
            }

            return computeDiff(head: head, buffer: currentText)
        }.value
    }

    /// Diffs two blobs via `git diff --no-index -U0` over temp files and parses
    /// the hunk headers into per-line kinds.
    private static func computeDiff(head: String, buffer: String) -> GitDiff? {
        let tmp = FileManager.default.temporaryDirectory
        let headURL = tmp.appendingPathComponent("brisk-head-\(UUID().uuidString)")
        let bufURL = tmp.appendingPathComponent("brisk-buf-\(UUID().uuidString)")
        defer {
            try? FileManager.default.removeItem(at: headURL)
            try? FileManager.default.removeItem(at: bufURL)
        }
        guard (try? head.write(to: headURL, atomically: true, encoding: .utf8)) != nil,
              (try? buffer.write(to: bufURL, atomically: true, encoding: .utf8)) != nil else { return nil }

        // --no-index always exits 1 when files differ, so ignore the status.
        guard let out = run(["diff", "--no-index", "--no-color", "-U0", "--", headURL.path, bufURL.path], allowFailure: true) else {
            return GitDiff()
        }

        var diff = GitDiff()
        for line in out.split(separator: "\n", omittingEmptySubsequences: false) where line.hasPrefix("@@") {
            guard let hunk = parseHunk(String(line)) else { continue }
            if hunk.oldCount == 0 {
                for l in hunk.newStart..<(hunk.newStart + max(hunk.newCount, 1)) { diff.lineKinds[l] = .added }
            } else if hunk.newCount == 0 {
                diff.deletions.insert(max(1, hunk.newStart))
            } else {
                for l in hunk.newStart..<(hunk.newStart + hunk.newCount) { diff.lineKinds[l] = .modified }
            }
        }
        return diff
    }

    private struct Hunk { let newStart: Int; let oldCount: Int; let newCount: Int }

    private static let hunkRegex = try? NSRegularExpression(
        pattern: #"^@@ -\d+(?:,(\d+))? \+(\d+)(?:,(\d+))? @@"#
    )

    private static func parseHunk(_ line: String) -> Hunk? {
        guard let regex = hunkRegex,
              let m = regex.firstMatch(in: line, range: NSRange(line.startIndex..., in: line)) else { return nil }
        func intGroup(_ i: Int, default def: Int) -> Int {
            let r = m.range(at: i)
            guard r.location != NSNotFound, let sr = Range(r, in: line) else { return def }
            return Int(line[sr]) ?? def
        }
        let oldCount = intGroup(1, default: 1)
        let newStart = intGroup(2, default: 1)
        let newCount = intGroup(3, default: 1)
        return Hunk(newStart: newStart, oldCount: oldCount, newCount: newCount)
    }

    /// Runs `git` with the given args and returns stdout, or nil on failure
    /// (unless `allowFailure`, where stdout is returned regardless of exit code).
    private static func run(_ args: [String], allowFailure: Bool = false) -> String? {
        guard let data = runData(args, allowFailure: allowFailure) else { return nil }
        return String(data: data, encoding: .utf8)
    }

    private static func runData(_ args: [String], allowFailure: Bool = false) -> Data? {
        guard let result = BoundedProcessRunner.run(
            executableURL: URL(fileURLWithPath: "/usr/bin/env"),
            arguments: ["git"] + args,
            timeout: 30,
            maximumStandardOutputBytes: 64 * 1024 * 1024,
            maximumStandardErrorBytes: 2 * 1024 * 1024
        ), !result.timedOut, !result.outputLimitExceeded,
           allowFailure || result.terminationStatus == 0 else { return nil }
        return result.stdout
    }
}
