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

/// Outcome of a git command that can fail in a way worth surfacing (push, pull,
/// checkout). `output` carries the combined stdout+stderr for the error banner.
struct GitResult: Sendable {
    let ok: Bool
    let output: String
}

/// Computes a git "gutter" diff by comparing the *current buffer* against the
/// committed `HEAD` blob — so it reflects uncommitted edits live, not just what
/// is saved. Shells out to the user's own `git`; returns nil outside a repo.
enum GitService {
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

            guard let out = run(["-C", top, "status", "--porcelain=v1"]) else {
                return GitStatus(branch: branch, upstream: upstream, ahead: ahead, behind: behind, hasRemote: hasRemote, changes: [])
            }
            var changes: [GitFileChange] = []
            for raw in out.split(separator: "\n", omittingEmptySubsequences: true) {
                let line = String(raw)
                guard line.count >= 4 else { continue }
                let chars = Array(line)
                let index = chars[0], worktree = chars[1]
                var path = String(line.dropFirst(3))
                // Renames render as "old -> new"; key on the new path.
                if let arrow = path.range(of: " -> ") { path = String(path[arrow.upperBound...]) }
                path = path.trimmingCharacters(in: CharacterSet(charactersIn: "\""))
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

    @discardableResult
    static func stage(_ path: String, root: URL) async -> Bool {
        await runVoid(["-C", root.path, "add", "--", path])
    }

    @discardableResult
    static func stageAll(root: URL) async -> Bool {
        await runVoid(["-C", root.path, "add", "-A"])
    }

    @discardableResult
    static func unstage(_ path: String, root: URL) async -> Bool {
        await runVoid(["-C", root.path, "restore", "--staged", "--", path])
    }

    /// Discards working-tree changes for a tracked file (destructive — the
    /// caller is expected to confirm first).
    @discardableResult
    static func discard(_ path: String, root: URL) async -> Bool {
        await runVoid(["-C", root.path, "restore", "--", path])
    }

    @discardableResult
    static func commit(message: String, root: URL) async -> Bool {
        await runVoid(["-C", root.path, "commit", "-m", message])
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

    static func checkout(_ branch: String, root: URL) async -> GitResult {
        await runResult(["-C", root.path, "checkout", branch])
    }

    static func createBranch(_ name: String, root: URL) async -> GitResult {
        await runResult(["-C", root.path, "checkout", "-b", name])
    }

    private static func runVoid(_ args: [String]) async -> Bool {
        await Task.detached(priority: .utility) { run(args) != nil }.value
    }

    /// Runs git capturing stdout+stderr and the exit status — for operations
    /// whose failure the UI should surface (push/pull/checkout).
    private static func runResult(_ args: [String]) async -> GitResult {
        await Task.detached(priority: .utility) { () -> GitResult in
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
            process.arguments = ["git"] + args
            let out = Pipe(), err = Pipe()
            process.standardOutput = out
            process.standardError = err
            do { try process.run() } catch {
                return GitResult(ok: false, output: error.localizedDescription)
            }
            let outData = out.fileHandleForReading.readDataToEndOfFile()
            let errData = err.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()
            let combined = ((String(data: outData, encoding: .utf8) ?? "") + (String(data: errData, encoding: .utf8) ?? ""))
                .trimmingCharacters(in: .whitespacesAndNewlines)
            return GitResult(ok: process.terminationStatus == 0, output: combined)
        }.value
    }

    static func diff(for fileURL: URL, currentText: String) async -> GitDiff? {
        let path = fileURL.path
        let dir = fileURL.deletingLastPathComponent().path
        return await Task.detached(priority: .utility) { () -> GitDiff? in
            guard let root = run(["-C", dir, "rev-parse", "--show-toplevel"])?
                .trimmingCharacters(in: .whitespacesAndNewlines), !root.isEmpty else { return nil }
            let relative = path.hasPrefix(root + "/") ? String(path.dropFirst(root.count + 1)) : fileURL.lastPathComponent

            // HEAD version of the file. Missing → file is new/untracked; mark
            // every line as added.
            let head = run(["-C", root, "show", "HEAD:\(relative)"])
            guard let head else {
                let count = currentText.isEmpty ? 0 : currentText.components(separatedBy: "\n").count
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
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = ["git"] + args
        let stdout = Pipe()
        let stderr = Pipe()
        process.standardOutput = stdout
        process.standardError = stderr
        do { try process.run() } catch { return nil }
        let data = stdout.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard allowFailure || process.terminationStatus == 0 else { return nil }
        return String(data: data, encoding: .utf8)
    }
}
