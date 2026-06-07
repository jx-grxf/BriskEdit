import Foundation

/// One match inside a file: a 1-based line/column, the matched length, and the
/// full line text for display (UTF-16 units, ready for `TextDocument.range`).
struct SearchMatch: Sendable, Hashable, Identifiable {
    let id = UUID()
    let line: Int
    let column: Int
    let length: Int
    let lineText: String
}

/// All matches found in one file, grouped for the results list.
struct SearchFileResult: Sendable, Identifiable {
    var id: URL { url }
    let url: URL
    let matches: [SearchMatch]
}

struct SearchQuery: Sendable, Equatable {
    var text: String
    var caseSensitive: Bool = false
    var wholeWord: Bool = false
    var isRegex: Bool = false
}

struct SearchResponse: Sendable {
    var results: [SearchFileResult]
    var errorMessage: String?
    var reachedMatchLimit: Bool
}

/// Project-wide text search. Prefers ripgrep (fast, .gitignore-aware) when it's
/// installed; otherwise falls back to a pure-Swift recursive scan that reuses
/// the file tree's ignore rules. Both run off the main actor.
enum SearchService {
    static func search(_ query: SearchQuery, root: URL, includeHidden: Bool, fileLimit: Int = 4000, matchLimit: Int = 5000) async -> [SearchFileResult] {
        await searchWithFeedback(query, root: root, includeHidden: includeHidden, fileLimit: fileLimit, matchLimit: matchLimit).results
    }

    static func searchWithFeedback(_ query: SearchQuery, root: URL, includeHidden: Bool, fileLimit: Int = 4000, matchLimit: Int = 5000) async -> SearchResponse {
        let trimmed = query.text
        guard !trimmed.isEmpty else { return SearchResponse(results: [], errorMessage: nil, reachedMatchLimit: false) }
        if query.isRegex, compile(query) == nil {
            return SearchResponse(results: [], errorMessage: "Invalid regular expression — turn off the .* button to search the text literally.", reachedMatchLimit: false)
        }
        return await Task.detached(priority: .userInitiated) {
            if let rg = ripgrepPath() {
                return ripgrepSearch(rg: rg, query: query, root: root, includeHidden: includeHidden, matchLimit: matchLimit)
            }
            return fallbackSearch(query: query, root: root, includeHidden: includeHidden, fileLimit: fileLimit, matchLimit: matchLimit)
        }.value
    }

    /// Rewrites every match in the given files on disk. Returns the number of
    /// files changed. Open tabs pick up the change via their file watchers.
    static func replaceAll(_ query: SearchQuery, replacement: String, in files: [URL]) async -> Int {
        guard !query.text.isEmpty else { return 0 }
        return await Task.detached(priority: .userInitiated) {
            guard let regex = compile(query) else { return 0 }
            var changed = 0
            for url in files {
                guard let original = try? String(contentsOf: url, encoding: .utf8) else { continue }
                let ns = original as NSString
                let template = query.isRegex ? replacement : NSRegularExpression.escapedTemplate(for: replacement)
                let updated = regex.stringByReplacingMatches(in: original, range: NSRange(location: 0, length: ns.length), withTemplate: template)
                if updated != original, (try? updated.write(to: url, atomically: true, encoding: .utf8)) != nil {
                    changed += 1
                }
            }
            return changed
        }.value
    }

    // MARK: - ripgrep

    private static func ripgrepPath() -> String? {
        let candidates = ["/opt/homebrew/bin/rg", "/usr/local/bin/rg", "/usr/bin/rg"]
        for path in candidates where FileManager.default.isExecutableFile(atPath: path) {
            return path
        }
        return nil
    }

    private static func ripgrepSearch(rg: String, query: SearchQuery, root: URL, includeHidden: Bool, matchLimit: Int) -> SearchResponse {
        var args = ["--json", "--line-number", "--column", "--max-filesize", "2M"]
        args.append(query.caseSensitive ? "--case-sensitive" : "--ignore-case")
        if query.wholeWord { args.append("--word-regexp") }
        if !query.isRegex { args.append("--fixed-strings") }
        if includeHidden { args.append("--hidden") }
        args.append(contentsOf: ["--glob", "!.git/*"])
        args.append("--")
        args.append(query.text)
        args.append(root.path)

        let process = Process()
        process.executableURL = URL(fileURLWithPath: rg)
        process.arguments = args
        let stdout = Pipe()
        process.standardOutput = stdout
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
        } catch {
            return SearchResponse(results: [], errorMessage: "Could not start ripgrep: \(error.localizedDescription)", reachedMatchLimit: false)
        }
        let timeout = DispatchWorkItem { [weak process] in
            guard let process, process.isRunning else { return }
            process.terminate()
        }
        DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + 30, execute: timeout)

        var byFile: [URL: [SearchMatch]] = [:]
        var order: [URL] = []
        var total = 0
        var reachedLimit = false
        var reachedResourceLimit = false
        var pending = Data()
        while true {
            let chunk = stdout.fileHandleForReading.availableData
            if chunk.isEmpty { break }
            pending.append(chunk)
            if pending.count > 8 * 1024 * 1024 {
                reachedResourceLimit = true
                process.terminate()
                break
            }
            while let newline = pending.firstIndex(of: 0x0a) {
                let lineData = pending[..<newline]
                pending.removeSubrange(...newline)
                guard let line = String(data: lineData, encoding: .utf8) else { continue }
                parseRipgrepLine(Substring(line), byFile: &byFile, order: &order, total: &total, matchLimit: matchLimit, reachedLimit: &reachedLimit)
                if reachedLimit {
                    process.terminate()
                    break
                }
            }
            if reachedLimit { break }
        }
        if !pending.isEmpty, reachedLimit == false, let line = String(data: pending, encoding: .utf8) {
            parseRipgrepLine(Substring(line), byFile: &byFile, order: &order, total: &total, matchLimit: matchLimit, reachedLimit: &reachedLimit)
        }
        process.waitUntilExit()
        timeout.cancel()

        let errorMessage: String?
        if reachedResourceLimit {
            errorMessage = "Search output exceeded the safety limit."
        } else if process.terminationStatus > 1, reachedLimit == false {
            errorMessage = "ripgrep exited with status \(process.terminationStatus)."
        } else {
            errorMessage = nil
        }

        return SearchResponse(
            results: order.map { SearchFileResult(url: $0, matches: byFile[$0] ?? []) },
            errorMessage: errorMessage,
            reachedMatchLimit: reachedLimit
        )
    }

    private static func parseRipgrepLine(
        _ rawLine: Substring,
        byFile: inout [URL: [SearchMatch]],
        order: inout [URL],
        total: inout Int,
        matchLimit: Int,
        reachedLimit: inout Bool
    ) {
        guard total < matchLimit,
              let lineData = rawLine.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: lineData) as? [String: Any],
              obj["type"] as? String == "match",
              let payload = obj["data"] as? [String: Any],
              let pathText = (payload["path"] as? [String: Any])?["text"] as? String,
              let lineNumber = payload["line_number"] as? Int,
              let linesText = (payload["lines"] as? [String: Any])?["text"] as? String,
              let submatches = payload["submatches"] as? [[String: Any]] else { return }
        let url = URL(fileURLWithPath: pathText)
        let lineBytes = Array(linesText.utf8)
        for sub in submatches {
            guard total < matchLimit else {
                reachedLimit = true
                return
            }
            guard let start = sub["start"] as? Int, let end = sub["end"] as? Int else { continue }
            let column = utf16Count(of: lineBytes, upTo: start) + 1
            let length = utf16Count(of: lineBytes, from: start, to: end)
            let match = SearchMatch(line: lineNumber, column: column, length: length, lineText: trimLine(linesText))
            if byFile[url] == nil { order.append(url) }
            byFile[url, default: []].append(match)
            total += 1
        }
        reachedLimit = total >= matchLimit
    }

    private static func utf16Count(of bytes: [UInt8], upTo byteOffset: Int) -> Int {
        let slice = bytes[0..<min(byteOffset, bytes.count)]
        return String(decoding: slice, as: UTF8.self).utf16.count
    }

    private static func utf16Count(of bytes: [UInt8], from: Int, to: Int) -> Int {
        let lo = min(from, bytes.count), hi = min(to, bytes.count)
        guard lo < hi else { return 0 }
        return String(decoding: bytes[lo..<hi], as: UTF8.self).utf16.count
    }

    // MARK: - Pure-Swift fallback

    private static func fallbackSearch(query: SearchQuery, root: URL, includeHidden: Bool, fileLimit: Int, matchLimit: Int) -> SearchResponse {
        guard let regex = compile(query) else {
            return SearchResponse(results: [], errorMessage: "Invalid regular expression — turn off the .* button to search the text literally.", reachedMatchLimit: false)
        }
        var results: [SearchFileResult] = []
        var total = 0
        for url in FileIndex.files(under: root, includeHidden: includeHidden, limit: fileLimit) {
            guard total < matchLimit else { break }
            guard let attrs = try? url.resourceValues(forKeys: [.fileSizeKey]), (attrs.fileSize ?? 0) <= 2_000_000 else { continue }
            guard let content = try? String(contentsOf: url, encoding: .utf8) else { continue }
            var matches: [SearchMatch] = []
            let ns = content as NSString
            // Track the 1-based line number as we walk lines in order, instead of
            // rescanning from the file start for every matching line (which made
            // the fallback O(n²) on large files).
            var currentLine = 0
            ns.enumerateSubstrings(in: NSRange(location: 0, length: ns.length), options: [.byLines]) { line, _, _, stop in
                currentLine += 1
                guard total < matchLimit else { stop.pointee = true; return }
                let lineText = (line ?? "")
                let lineNS = lineText as NSString
                regex.enumerateMatches(in: lineText, range: NSRange(location: 0, length: lineNS.length)) { match, _, _ in
                    guard let match else { return }
                    matches.append(SearchMatch(line: currentLine, column: match.range.location + 1, length: match.range.length, lineText: trimLine(lineText)))
                    total += 1
                }
            }
            if !matches.isEmpty { results.append(SearchFileResult(url: url, matches: matches)) }
        }
        return SearchResponse(results: results, errorMessage: nil, reachedMatchLimit: total >= matchLimit)
    }

    private static func compile(_ query: SearchQuery) -> NSRegularExpression? {
        var pattern = query.isRegex ? query.text : NSRegularExpression.escapedPattern(for: query.text)
        if query.wholeWord { pattern = "\\b(?:\(pattern))\\b" }
        var options: NSRegularExpression.Options = []
        if !query.caseSensitive { options.insert(.caseInsensitive) }
        return try? NSRegularExpression(pattern: pattern, options: options)
    }

    private static func trimLine(_ text: String) -> String {
        let trimmed = text.trimmingCharacters(in: CharacterSet(charactersIn: "\n\r"))
        return trimmed.count > 400 ? String(trimmed.prefix(400)) : trimmed
    }
}
