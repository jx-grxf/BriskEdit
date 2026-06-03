import AppKit

// MARK: - Hex parsing / formatting

extension NSColor {
    /// Parses `#RGB`, `#RGBA`, `#RRGGBB` and `#RRGGBBAA` (with or without the
    /// leading `#`). Returns nil for anything it can't make sense of.
    convenience init?(hexString raw: String) {
        var s = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if s.hasPrefix("#") { s.removeFirst() }
        guard s.allSatisfy({ $0.isHexDigit }) else { return nil }

        func expand(_ str: String) -> String {
            // #RGB / #RGBA → #RRGGBB / #RRGGBBAA
            str.map { "\($0)\($0)" }.joined()
        }

        switch s.count {
        case 3, 4: s = expand(s)
        case 6, 8: break
        default: return nil
        }

        guard let value = UInt64(s, radix: 16) else { return nil }
        let r, g, b, a: CGFloat
        if s.count == 8 {
            r = CGFloat((value >> 24) & 0xFF) / 255
            g = CGFloat((value >> 16) & 0xFF) / 255
            b = CGFloat((value >> 8) & 0xFF) / 255
            a = CGFloat(value & 0xFF) / 255
        } else {
            r = CGFloat((value >> 16) & 0xFF) / 255
            g = CGFloat((value >> 8) & 0xFF) / 255
            b = CGFloat(value & 0xFF) / 255
            a = 1
        }
        self.init(srgbRed: r, green: g, blue: b, alpha: a)
    }

    /// `#RRGGBB` or `#RRGGBBAA` (alpha appended only when not fully opaque).
    var hexString: String {
        guard let c = usingColorSpace(.sRGB) else { return "#000000" }
        let r = Int((c.redComponent * 255).rounded())
        let g = Int((c.greenComponent * 255).rounded())
        let b = Int((c.blueComponent * 255).rounded())
        let a = Int((c.alphaComponent * 255).rounded())
        if a >= 255 {
            return String(format: "#%02X%02X%02X", r, g, b)
        }
        return String(format: "#%02X%02X%02X%02X", r, g, b, a)
    }
}

// MARK: - Codable snapshot (imported themes round-trip through disk)

/// On-disk form of an imported theme. Colors are stored as hex strings so the
/// file stays human-readable and forward-compatible.
struct ColorThemeData: Codable, Equatable {
    var id: String
    var name: String
    var isDark: Bool
    var background, foreground, cursor, selection: String
    var gutterBackground, gutterForeground, currentLineHighlight: String
    var keyword, controlKeyword, type, function, preprocessor, string, number, comment: String
    var gitAdded, gitModified, gitDeleted: String

    init(_ t: ColorTheme) {
        id = t.id; name = t.name; isDark = t.isDark
        background = t.background.hexString
        foreground = t.foreground.hexString
        cursor = t.cursor.hexString
        selection = t.selection.hexString
        gutterBackground = t.gutterBackground.hexString
        gutterForeground = t.gutterForeground.hexString
        currentLineHighlight = t.currentLineHighlight.hexString
        keyword = t.keyword.hexString
        controlKeyword = t.controlKeyword.hexString
        type = t.type.hexString
        function = t.function.hexString
        preprocessor = t.preprocessor.hexString
        string = t.string.hexString
        number = t.number.hexString
        comment = t.comment.hexString
        gitAdded = t.gitAdded.hexString
        gitModified = t.gitModified.hexString
        gitDeleted = t.gitDeleted.hexString
    }

    var theme: ColorTheme {
        func c(_ s: String, _ fallback: UInt32) -> NSColor { NSColor(hexString: s) ?? ColorTheme.hex(fallback) }
        return ColorTheme(
            id: id, name: name, isDark: isDark, isBuiltIn: false,
            background: c(background, 0x1E1E1E), foreground: c(foreground, 0xD4D4D4),
            cursor: c(cursor, 0xAEAFAD), selection: c(selection, 0x264F78),
            gutterBackground: c(gutterBackground, 0x1E1E1E), gutterForeground: c(gutterForeground, 0x6E7681),
            currentLineHighlight: c(currentLineHighlight, 0x2A2A2A),
            keyword: c(keyword, 0x569CD6), controlKeyword: c(controlKeyword, 0xC586C0),
            type: c(type, 0x4EC9B0), function: c(function, 0xDCDCAA),
            preprocessor: c(preprocessor, 0xC586C0), string: c(string, 0xCE9178),
            number: c(number, 0xB5CEA8), comment: c(comment, 0x6A9955),
            gitAdded: c(gitAdded, 0x4BB543), gitModified: c(gitModified, 0x4A9EFF),
            gitDeleted: c(gitDeleted, 0xE5534B)
        )
    }
}

// MARK: - VS Code theme importer

enum VSCodeThemeImporter {
    enum ImportError: LocalizedError {
        case unreadable
        case noColors

        var errorDescription: String? {
            switch self {
            case .unreadable: "The file isn't a valid VS Code color theme (`.json`)."
            case .noColors: "The theme file doesn't define any editor colors."
            }
        }
    }

    /// Parses a VS Code color-theme `.json`/`.jsonc` into a `ColorTheme`.
    /// Tolerates `//` and `/* */` comments and trailing commas (JSONC).
    static func theme(fromJSON data: Data, id: String, fallbackName: String) throws -> ColorTheme {
        let cleaned = stripJSONC(String(decoding: data, as: UTF8.self))
        guard
            let obj = try? JSONSerialization.jsonObject(with: Data(cleaned.utf8)),
            let root = obj as? [String: Any]
        else { throw ImportError.unreadable }

        let workbench = (root["colors"] as? [String: Any]) ?? [:]
        let tokens = parseTokenColors(root["tokenColors"] as? [[String: Any]] ?? [])
        guard !workbench.isEmpty || !tokens.pairs.isEmpty else { throw ImportError.noColors }

        let isDark = (root["type"] as? String)?.lowercased() != "light"
        let name = (root["name"] as? String).flatMap { $0.isEmpty ? nil : $0 } ?? fallbackName

        // Sensible per-mode fallbacks so a sparse theme still renders.
        let fgFallback = ColorTheme.hex(isDark ? 0xD4D4D4 : 0x1F1F1F)
        let bgFallback = ColorTheme.hex(isDark ? 0x1E1E1E : 0xFFFFFF)

        func wb(_ keys: String..., fallback: NSColor) -> NSColor {
            for k in keys {
                if let hex = workbench[k] as? String, let c = NSColor(hexString: hex) { return c }
            }
            return fallback
        }

        let foreground = wb("editor.foreground", fallback: fgFallback)
        let background = wb("editor.background", fallback: bgFallback)

        func token(_ scopes: [String], _ fallback: NSColor) -> NSColor {
            tokens.color(forAnyOf: scopes) ?? fallback
        }

        return ColorTheme(
            id: id,
            name: name,
            isDark: isDark,
            isBuiltIn: false,
            background: background,
            foreground: foreground,
            cursor: wb("editorCursor.foreground", "editor.foreground", fallback: foreground),
            selection: wb("editor.selectionBackground", fallback: ColorTheme.hex(isDark ? 0x264F78 : 0xADD6FF)),
            gutterBackground: wb("editorGutter.background", "editor.background", fallback: background),
            gutterForeground: wb("editorLineNumber.foreground", fallback: ColorTheme.hex(isDark ? 0x6E7681 : 0xB0B0B0)),
            currentLineHighlight: wb("editor.lineHighlightBackground",
                                     fallback: (isDark ? NSColor(white: 1, alpha: 0.05) : NSColor(white: 0, alpha: 0.04))),
            keyword: token(["storage.type", "storage.modifier", "keyword", "storage"], foreground),
            controlKeyword: token(["keyword.control", "keyword"], token(["storage.type", "keyword"], foreground)),
            type: token(["entity.name.type", "entity.name.class", "support.type", "support.class", "entity.name"], foreground),
            function: token(["entity.name.function", "support.function", "meta.function-call"], foreground),
            preprocessor: token(["meta.preprocessor", "keyword.control.directive", "entity.name.function.preprocessor"], foreground),
            string: token(["string"], foreground),
            number: token(["constant.numeric", "constant"], foreground),
            comment: token(["comment"], ColorTheme.hex(isDark ? 0x6A9955 : 0x008000)),
            gitAdded: wb("editorGutter.addedBackground", "gitDecoration.addedResourceForeground", fallback: ColorTheme.hex(0x4BB543)),
            gitModified: wb("editorGutter.modifiedBackground", "gitDecoration.modifiedResourceForeground", fallback: ColorTheme.hex(0x4A9EFF)),
            gitDeleted: wb("editorGutter.deletedBackground", "gitDecoration.deletedResourceForeground", fallback: ColorTheme.hex(0xE5534B))
        )
    }

    // MARK: TextMate token-color matching

    /// Flattened (scope, color) pairs from `tokenColors`, in document order.
    private struct TokenColors {
        let pairs: [(scope: String, color: NSColor)]

        /// First requested scope that resolves, using TextMate prefix matching:
        /// a rule scope `keyword` matches the query `keyword.control`. The most
        /// specific (longest) matching rule wins.
        func color(forAnyOf queries: [String]) -> NSColor? {
            for q in queries {
                var best: (length: Int, color: NSColor)?
                for pair in pairs where q == pair.scope || q.hasPrefix(pair.scope + ".") {
                    if best == nil || pair.scope.count > best!.length {
                        best = (pair.scope.count, pair.color)
                    }
                }
                if let best { return best.color }
            }
            return nil
        }
    }

    private static func parseTokenColors(_ entries: [[String: Any]]) -> TokenColors {
        var pairs: [(String, NSColor)] = []
        for entry in entries {
            guard
                let settings = entry["settings"] as? [String: Any],
                let fg = settings["foreground"] as? String,
                let color = NSColor(hexString: fg)
            else { continue }

            let scopes: [String]
            switch entry["scope"] {
            case let s as String: scopes = s.split(whereSeparator: { $0 == "," }).map { $0.trimmingCharacters(in: .whitespaces) }
            case let arr as [String]: scopes = arr
            default: continue
            }
            for scope in scopes where !scope.isEmpty {
                pairs.append((scope, color))
            }
        }
        return TokenColors(pairs: pairs)
    }

    // MARK: JSONC cleanup

    /// Strips `//` line comments, `/* */` block comments and trailing commas so
    /// `JSONSerialization` accepts VS Code's JSONC theme files. String contents
    /// (and escaped quotes) are preserved.
    static func stripJSONC(_ input: String) -> String {
        var out = String(); out.reserveCapacity(input.count)
        var inString = false
        var escaped = false
        var i = input.startIndex
        while i < input.endIndex {
            let c = input[i]
            if inString {
                out.append(c)
                if escaped { escaped = false }
                else if c == "\\" { escaped = true }
                else if c == "\"" { inString = false }
                i = input.index(after: i)
                continue
            }
            if c == "\"" {
                inString = true; out.append(c); i = input.index(after: i); continue
            }
            let next = input.index(after: i)
            if c == "/", next < input.endIndex {
                if input[next] == "/" {
                    while i < input.endIndex, input[i] != "\n" { i = input.index(after: i) }
                    continue
                }
                if input[next] == "*" {
                    i = input.index(after: next)
                    while i < input.endIndex {
                        if input[i] == "*", input.index(after: i) < input.endIndex, input[input.index(after: i)] == "/" {
                            i = input.index(i, offsetBy: 2); break
                        }
                        i = input.index(after: i)
                    }
                    continue
                }
            }
            out.append(c)
            i = input.index(after: i)
        }
        return removeTrailingCommas(out)
    }

    private static func removeTrailingCommas(_ input: String) -> String {
        var out = String(); out.reserveCapacity(input.count)
        var inString = false
        var escaped = false
        let chars = Array(input)
        var idx = 0
        while idx < chars.count {
            let c = chars[idx]
            if inString {
                out.append(c)
                if escaped { escaped = false }
                else if c == "\\" { escaped = true }
                else if c == "\"" { inString = false }
                idx += 1
                continue
            }
            if c == "\"" { inString = true; out.append(c); idx += 1; continue }
            if c == "," {
                // Look ahead past whitespace for a closing bracket.
                var j = idx + 1
                while j < chars.count, chars[j].isWhitespace { j += 1 }
                if j < chars.count, chars[j] == "}" || chars[j] == "]" {
                    idx += 1 // drop the comma
                    continue
                }
            }
            out.append(c)
            idx += 1
        }
        return out
    }
}
