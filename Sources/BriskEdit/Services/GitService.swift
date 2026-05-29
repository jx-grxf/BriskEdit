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

/// Computes a git "gutter" diff by comparing the *current buffer* against the
/// committed `HEAD` blob — so it reflects uncommitted edits live, not just what
/// is saved. Shells out to the user's own `git`; returns nil outside a repo.
enum GitService {
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
