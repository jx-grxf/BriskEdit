import Foundation

/// Parses `.editorconfig` files and resolves the per-file indentation and
/// whitespace settings for a document. Supports the common subset: `root`,
/// simple globs (`*`, `*.ext`, exact names) and the standard properties.
enum EditorConfigService {
    static let fileName = ".editorconfig"

    enum IndentStyle: String, Sendable {
        case space
        case tab
    }

    /// The resolved, merged settings for one file. `nil` fields fall back to
    /// the user's global preferences at the call site.
    struct Settings: Equatable, Sendable {
        var indentStyle: IndentStyle?
        var indentSize: Int?
        /// `indent_size = tab`: the width is defined by `tab_width`.
        var indentSizeIsTab = false
        var tabWidth: Int?
        var endOfLine: String?
        var insertFinalNewline: Bool?
        var trimTrailingWhitespace: Bool?

        var usesSpacesForIndentation: Bool? {
            switch indentStyle {
            case .space: true
            case .tab: false
            case nil: nil
            }
        }

        var indentWidth: Int? {
            if indentSizeIsTab { return tabWidth }
            return indentSize ?? tabWidth
        }
    }

    /// One `[section]` of an `.editorconfig` file: a filename pattern plus the
    /// properties declared beneath it.
    struct Section: Equatable, Sendable {
        let pattern: String
        let properties: [String: String]
    }

    struct ParsedFile: Equatable, Sendable {
        var isRoot = false
        var sections: [Section] = []
    }

    // MARK: - Parsing

    static func parse(_ source: String) -> ParsedFile {
        var result = ParsedFile()
        var currentPattern: String?
        var currentProperties: [String: String] = [:]

        func flushSection() {
            if let pattern = currentPattern {
                result.sections.append(Section(pattern: pattern, properties: currentProperties))
            }
            currentProperties = [:]
        }

        for rawLine in source.split(separator: "\n", omittingEmptySubsequences: false) {
            let line = stripComment(String(rawLine)).trimmingCharacters(in: .whitespacesAndNewlines)
            guard !line.isEmpty else { continue }
            if line.hasPrefix("[") && line.hasSuffix("]") {
                flushSection()
                currentPattern = String(line.dropFirst().dropLast())
                continue
            }
            guard let separator = line.firstIndex(where: { $0 == "=" || $0 == ":" }) else { continue }
            let key = line[..<separator].trimmingCharacters(in: .whitespaces).lowercased()
            let value = line[line.index(after: separator)...].trimmingCharacters(in: .whitespaces)
            guard !key.isEmpty else { continue }
            if currentPattern == nil {
                if key == "root" {
                    result.isRoot = value.lowercased() == "true"
                }
                continue
            }
            currentProperties[key] = value
        }
        flushSection()
        return result
    }

    private static func stripComment(_ line: String) -> String {
        guard let index = line.firstIndex(where: { $0 == ";" || $0 == "#" }) else { return line }
        return String(line[..<index])
    }

    // MARK: - Matching

    /// Pattern matching limited to the common cases: exact names, `*` (any run
    /// of characters except `/`) and `?` (single character).
    static func matches(pattern: String, fileName: String) -> Bool {
        if pattern == fileName { return true }
        guard pattern.contains("*") || pattern.contains("?") else { return false }
        var regex = "^"
        for character in pattern {
            switch character {
            case "*": regex += "[^/]*"
            case "?": regex += "[^/]"
            default: regex += NSRegularExpression.escapedPattern(for: String(character))
            }
        }
        regex += "$"
        return range(of: regex, in: fileName) != nil
    }

    private static func range(of pattern: String, in fileName: String) -> NSRange? {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { return nil }
        return regex.firstMatch(in: fileName, options: [], range: NSRange(fileName.startIndex..., in: fileName))?.range
    }

    /// The last matching section in a file wins over earlier ones.
    static func matchingProperties(in file: ParsedFile, fileName: String) -> [String: String] {
        var properties: [String: String] = [:]
        for section in file.sections where matches(pattern: section.pattern, fileName: fileName) {
            for (key, value) in section.properties {
                properties[key] = value
            }
        }
        return properties
    }

    // MARK: - Resolution

    static func settings(for fileURL: URL?, workspaceRoot: URL?) -> Settings {
        guard let fileURL, fileURL.isFileURL else { return Settings() }
        let directories = candidateDirectories(from: fileURL.deletingLastPathComponent(), upTo: workspaceRoot)
        let name = fileURL.lastPathComponent
        var settings = Settings()
        for directory in directories.reversed() {
            guard let parsed = cachedParsedFile(in: directory) else { continue }
            apply(matchingProperties(in: parsed, fileName: name), to: &settings)
        }
        return settings
    }

    /// Directories to inspect, ordered innermost-first, stopping at the workspace
    /// root, at a `root = true` config or at the filesystem root.
    static func candidateDirectories(from directory: URL, upTo workspaceRoot: URL?) -> [URL] {
        var chain: [URL] = []
        var current = directory.standardizedFileURL
        let rootPath = workspaceRoot.map { $0.standardizedFileURL.path }
        while chain.count < 64 {
            chain.append(current)
            if let rootPath, current.path == rootPath || !current.path.hasPrefix(rootPath + "/") {
                break
            }
            if cachedParsedFile(in: current)?.isRoot == true { break }
            let parent = current.deletingLastPathComponent()
            if parent.path == current.path { break }
            current = parent
        }
        return chain
    }

    private static func apply(_ properties: [String: String], to settings: inout Settings) {
        for (key, value) in properties {
            switch key {
            case "indent_style":
                settings.indentStyle = IndentStyle(rawValue: value.lowercased())
            case "indent_size":
                if value.lowercased() == "tab" {
                    settings.indentSizeIsTab = true
                    settings.indentSize = nil
                } else if let width = Int(value) {
                    settings.indentSizeIsTab = false
                    settings.indentSize = width
                }
            case "tab_width":
                settings.tabWidth = Int(value)
            case "end_of_line":
                let normalized = value.lowercased()
                if ["lf", "crlf", "cr"].contains(normalized) {
                    settings.endOfLine = normalized
                }
            case "insert_final_newline":
                settings.insertFinalNewline = Self.boolValue(value)
            case "trim_trailing_whitespace":
                settings.trimTrailingWhitespace = Self.boolValue(value)
            default:
                break
            }
        }
    }

    private static func boolValue(_ value: String) -> Bool? {
        switch value.lowercased() {
        case "true": true
        case "false": false
        default: nil
        }
    }

    // MARK: - Cache

    /// Parsed configs keyed by directory, revalidated against the file's
    /// modification date so edits to `.editorconfig` are picked up cheaply.
    private final class Cache: @unchecked Sendable {
        private struct Entry {
            let modifiedAt: Date?
            let parsed: ParsedFile
        }

        private let lock = NSLock()
        private var entries: [String: Entry] = [:]

        func parsedFile(in directory: URL) -> ParsedFile? {
            let url = directory.appendingPathComponent(fileName)
            let attributes = try? FileManager.default.attributesOfItem(atPath: url.path)
            let modifiedAt = attributes?[.modificationDate] as? Date
            lock.lock()
            defer { lock.unlock() }
            if let entry = entries[directory.path], entry.modifiedAt == modifiedAt {
                return entry.parsed
            }
            guard let source = try? String(contentsOf: url, encoding: .utf8) else {
                entries.removeValue(forKey: directory.path)
                return nil
            }
            let parsed = parse(source)
            entries[directory.path] = Entry(modifiedAt: modifiedAt, parsed: parsed)
            return parsed
        }
    }

    private static let cache = Cache()

    private static func cachedParsedFile(in directory: URL) -> ParsedFile? {
        cache.parsedFile(in: directory)
    }
}
