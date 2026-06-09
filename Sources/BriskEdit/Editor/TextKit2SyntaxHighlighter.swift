import AppKit

@MainActor
enum TextKit2SyntaxHighlighter {
    private static let maxHighlightedCharacters = 500_000

    /// Compiled-regex cache so patterns aren't rebuilt on every keystroke.
    private static var regexCache: [String: NSRegularExpression] = [:]

    private static func regex(_ pattern: String, options: NSRegularExpression.Options) -> NSRegularExpression? {
        let key = "\(options.rawValue)|\(pattern)"
        if let cached = regexCache[key] { return cached }
        guard let compiled = try? NSRegularExpression(pattern: pattern, options: options) else { return nil }
        regexCache[key] = compiled
        return compiled
    }

    /// Paints display-only color via the layout manager's *rendering attributes*,
    /// which (unlike text-storage edits) never invalidate layout — the key to
    /// flicker-free highlighting on TextKit 2.
    @MainActor
    struct RenderingPainter {
        let layoutManager: NSTextLayoutManager
        let contentManager: NSTextContentManager
        let documentStart: NSTextLocation

        init?(textView: NSTextView) {
            guard let layoutManager = textView.textLayoutManager,
                  let contentManager = layoutManager.textContentManager else { return nil }
            self.layoutManager = layoutManager
            self.contentManager = contentManager
            self.documentStart = contentManager.documentRange.location
        }

        /// Drops all color overrides so untouched tokens fall back to the storage's
        /// base foreground color.
        func reset() {
            layoutManager.invalidateRenderingAttributes(for: contentManager.documentRange)
        }

        func paint(_ attributes: [NSAttributedString.Key: Any], range: NSRange) {
            guard let start = contentManager.location(documentStart, offsetBy: range.location),
                  let end = contentManager.location(start, offsetBy: range.length),
                  let textRange = NSTextRange(location: start, end: end) else { return }
            layoutManager.setRenderingAttributes(attributes, for: textRange)
        }
    }

    /// Recolors the whole document using TextKit 2 **rendering attributes**
    /// (display-only color overrides on the layout manager) instead of mutating
    /// the text storage. Storage edits invalidate layout fragments — even for
    /// off-screen text — which made the viewport churn and the visible text
    /// flash/jitter (a line popping in and out) while typing. Rendering
    /// attributes never touch layout, so highlighting is invisible to the
    /// viewport controller: no flash, no jitter, and we can color the entire
    /// document again (correct for multi-line comments/strings).
    ///
    /// Skipped for plain text and very large files, which then render with the
    /// text view's uniform color.
    static func apply(to textView: NSTextView, language: SourceLanguage, theme: EditorTheme) {
        guard let painter = RenderingPainter(textView: textView),
              let storage = textView.textContentStorage?.textStorage else { return }
        // Clear previous colors first so removed tokens fall back to the base
        // foreground (the text storage's own color).
        painter.reset()
        let length = storage.length
        guard length > 0, length <= maxHighlightedCharacters, language != .plainText else {
            textView.typingAttributes = baseAttributes(theme: theme)
            return
        }
        let source = storage.string as NSString
        let range = NSRange(location: 0, length: length)
        // Order matters: later passes win on overlapping ranges, so tokens that
        // must always survive (strings, comments) run last.
        highlightFunctions(with: painter, source: source, range: range, language: language, color: theme.function)
        highlightTypes(with: painter, source: source, range: range, language: language, color: theme.type)
        highlightKeywords(with: painter, source: source, range: range, language: language, theme: theme)
        highlightNumbers(with: painter, source: source, range: range, color: theme.number)
        highlightPreprocessor(with: painter, source: source, range: range, language: language, color: theme.preprocessor)
        highlightStrings(with: painter, source: source, range: range, color: theme.string)
        highlightComments(with: painter, source: source, range: range, language: language, color: theme.comment)
        textView.typingAttributes = baseAttributes(theme: theme)
    }

    private static func baseAttributes(theme: EditorTheme) -> [NSAttributedString.Key: Any] {
        [
            .font: theme.nsFont,
            .foregroundColor: theme.foreground,
            .paragraphStyle: theme.paragraphStyle
        ]
    }

    private static func highlightComments(with painter: RenderingPainter, source: NSString, range: NSRange, language: SourceLanguage, color: NSColor) {
        let patterns: [String]
        switch language {
        case .markdown, .html, .xml:
            patterns = ["<!--(?s:.*?)-->"]
        case .python, .shell, .yaml, .ruby, .perl, .toml:
            patterns = ["#.*$"]
        case .ini:
            patterns = ["[#;].*$"]
        case .lua:
            patterns = ["--\\[\\[(?s:.*?)\\]\\]", "--.*$"]
        case .sql:
            patterns = ["--.*$", "/\\*(?s:.*?)\\*/"]
        default:
            patterns = ["//.*$", "/\\*(?s:.*?)\\*/"]
        }
        apply(patterns: patterns, with: painter, source: source, range: range, options: [.anchorsMatchLines], attributes: [.foregroundColor: color])
    }

    private static func highlightStrings(with painter: RenderingPainter, source: NSString, range: NSRange, color: NSColor) {
        apply(patterns: ["\"(?:\\\\.|[^\"\\\\])*\"", "'(?:\\\\.|[^'\\\\])*'", "<[A-Za-z0-9_./]+\\.h>"], with: painter, source: source, range: range, attributes: [.foregroundColor: color])
    }

    private static func highlightNumbers(with painter: RenderingPainter, source: NSString, range: NSRange, color: NSColor) {
        apply(patterns: ["\\b0[xX][0-9a-fA-F]+\\b", "\\b\\d+(?:\\.\\d+)?(?:[eE][-+]?\\d+)?[fFuUlL]*\\b"], with: painter, source: source, range: range, attributes: [.foregroundColor: color])
    }

    private static func highlightPreprocessor(with painter: RenderingPainter, source: NSString, range: NSRange, language: SourceLanguage, color: NSColor) {
        guard language == .c || language == .cpp else { return }
        // Color only the `#directive` token so the included path stays a string.
        applyCaptureGroup(
            pattern: "^(\\s*#\\s*(?:include|define|if|ifdef|ifndef|else|elif|endif|pragma|undef|error|warning))\\b",
            group: 1,
            with: painter,
            source: source,
            range: range,
            options: [.anchorsMatchLines],
            attributes: [.foregroundColor: color]
        )
    }

    private static func highlightFunctions(with painter: RenderingPainter, source: NSString, range: NSRange, language: SourceLanguage, color: NSColor) {
        switch language {
        case .markdown, .yaml, .json, .html, .xml, .css, .plainText:
            return
        default:
            break
        }
        applyCaptureGroup(pattern: "\\b([A-Za-z_][A-Za-z0-9_]*)\\s*(?=\\()", group: 1, with: painter, source: source, range: range, attributes: [.foregroundColor: color])
    }

    private static func highlightTypes(with painter: RenderingPainter, source: NSString, range: NSRange, language: SourceLanguage, color: NSColor) {
        switch language {
        case .markdown, .yaml, .json, .html, .xml, .css, .shell, .plainText:
            return
        default:
            break
        }
        // CamelCase identifiers (types/classes) and C `_t` suffixed types.
        apply(patterns: ["\\b[A-Z][A-Za-z0-9_]*\\b", "\\b[a-z_][A-Za-z0-9_]*_t\\b"], with: painter, source: source, range: range, attributes: [.foregroundColor: color])
    }

    private static func highlightKeywords(with painter: RenderingPainter, source: NSString, range: NSRange, language: SourceLanguage, theme: EditorTheme) {
        let (keywords, control) = keywordSets(for: language)
        if !keywords.isEmpty {
            let escaped = keywords.map(NSRegularExpression.escapedPattern(for:)).joined(separator: "|")
            apply(patterns: ["\\b(\(escaped))\\b"], with: painter, source: source, range: range, attributes: [.foregroundColor: theme.keyword])
        }
        if !control.isEmpty {
            let escaped = control.map(NSRegularExpression.escapedPattern(for:)).joined(separator: "|")
            apply(patterns: ["\\b(\(escaped))\\b"], with: painter, source: source, range: range, attributes: [.foregroundColor: theme.controlKeyword])
        }
    }

    /// Returns (declaration/storage keywords, control-flow keywords) so each
    /// group can be colored separately, mirroring VS Code's Dark+ scheme.
    private static func keywordSets(for language: SourceLanguage) -> ([String], [String]) {
        let control: [String]
        let keywords: [String]
        switch language {
        case .c, .cpp:
            control = ["break", "case", "continue", "default", "do", "else", "for", "goto", "if", "return", "switch", "while"]
            keywords = ["auto", "char", "const", "double", "enum", "extern", "float", "inline", "int", "long", "short", "signed", "sizeof", "static", "struct", "typedef", "union", "unsigned", "void", "class", "namespace", "template", "typename", "using", "public", "private", "protected", "virtual", "new", "delete", "this", "nullptr", "bool", "true", "false"]
        case .swift:
            control = ["break", "case", "catch", "continue", "default", "do", "else", "fallthrough", "for", "guard", "if", "return", "switch", "throw", "try", "while", "await"]
            keywords = ["actor", "as", "async", "class", "enum", "extension", "false", "func", "import", "in", "let", "nil", "private", "protocol", "public", "self", "static", "struct", "throws", "true", "var", "internal", "final", "override", "init", "deinit", "lazy", "weak", "some", "any"]
        case .javascript, .typescript:
            control = ["break", "case", "catch", "continue", "default", "do", "else", "for", "if", "return", "switch", "throw", "try", "while", "await", "yield"]
            keywords = ["async", "class", "const", "export", "extends", "false", "function", "import", "in", "instanceof", "let", "new", "null", "of", "static", "super", "this", "true", "type", "typeof", "var", "void", "interface", "enum", "implements"]
        case .php:
            control = ["break", "case", "continue", "default", "do", "else", "elseif", "for", "foreach", "if", "return", "switch", "while", "try", "catch", "throw"]
            keywords = ["abstract", "array", "class", "const", "echo", "extends", "false", "function", "implements", "interface", "namespace", "new", "null", "private", "protected", "public", "static", "true", "use", "var"]
        case .python:
            control = ["break", "continue", "elif", "else", "except", "finally", "for", "if", "raise", "return", "try", "while", "with", "yield", "pass"]
            keywords = ["and", "as", "async", "await", "class", "def", "False", "from", "global", "import", "in", "is", "lambda", "None", "nonlocal", "not", "or", "True"]
        case .rust:
            control = ["break", "continue", "else", "for", "if", "loop", "match", "return", "while"]
            keywords = ["as", "async", "await", "const", "crate", "enum", "false", "fn", "impl", "let", "mod", "move", "mut", "pub", "ref", "self", "static", "struct", "trait", "true", "type", "use", "where", "dyn", "Box"]
        case .go:
            control = ["break", "case", "continue", "default", "else", "fallthrough", "for", "goto", "if", "range", "return", "select", "switch"]
            keywords = ["chan", "const", "defer", "func", "go", "import", "interface", "map", "package", "struct", "type", "var", "nil", "true", "false"]
        case .java:
            control = ["break", "case", "catch", "continue", "default", "do", "else", "finally", "for", "if", "return", "switch", "throw", "try", "while"]
            keywords = ["abstract", "class", "enum", "extends", "final", "implements", "import", "instanceof", "interface", "native", "new", "package", "private", "protected", "public", "static", "super", "synchronized", "this", "throws", "transient", "void", "volatile", "boolean", "byte", "char", "double", "float", "int", "long", "short", "true", "false", "null", "var", "record", "sealed"]
        case .kotlin:
            control = ["break", "catch", "continue", "do", "else", "finally", "for", "if", "return", "throw", "try", "when", "while"]
            keywords = ["abstract", "as", "class", "companion", "const", "data", "enum", "fun", "import", "in", "interface", "internal", "is", "lateinit", "object", "open", "override", "package", "private", "protected", "public", "sealed", "suspend", "val", "var", "vararg", "by", "true", "false", "null", "this", "super"]
        case .ruby:
            control = ["begin", "break", "case", "else", "elsif", "ensure", "for", "if", "next", "redo", "rescue", "retry", "return", "unless", "until", "when", "while", "yield"]
            keywords = ["alias", "and", "attr_accessor", "attr_reader", "attr_writer", "class", "def", "do", "end", "module", "nil", "not", "or", "require", "require_relative", "self", "super", "then", "true", "false", "lambda", "proc"]
        case .lua:
            control = ["break", "do", "else", "elseif", "end", "for", "goto", "if", "repeat", "return", "then", "until", "while"]
            keywords = ["and", "false", "function", "in", "local", "nil", "not", "or", "true", "self", "require"]
        case .sql:
            control = ["CASE", "WHEN", "THEN", "ELSE", "END", "IF", "WHILE", "LOOP"]
            keywords = ["SELECT", "FROM", "WHERE", "INSERT", "INTO", "VALUES", "UPDATE", "SET", "DELETE", "CREATE", "TABLE", "VIEW", "INDEX", "ALTER", "DROP", "JOIN", "INNER", "LEFT", "RIGHT", "OUTER", "ON", "GROUP", "BY", "ORDER", "HAVING", "LIMIT", "OFFSET", "DISTINCT", "AS", "AND", "OR", "NOT", "NULL", "PRIMARY", "KEY", "FOREIGN", "REFERENCES", "DEFAULT", "UNIQUE", "INT", "INTEGER", "VARCHAR", "TEXT", "BOOLEAN", "TIMESTAMP", "DATE"]
        case .perl:
            control = ["if", "elsif", "else", "unless", "for", "foreach", "while", "until", "do", "return", "last", "next", "redo"]
            keywords = ["use", "no", "my", "our", "local", "sub", "package", "require", "print", "printf", "say", "undef", "qw"]
        case .dart:
            control = ["break", "case", "catch", "continue", "default", "do", "else", "finally", "for", "if", "return", "switch", "throw", "try", "while", "await", "yield"]
            keywords = ["abstract", "as", "async", "class", "const", "enum", "extends", "factory", "final", "get", "implements", "import", "is", "late", "library", "mixin", "new", "set", "static", "super", "this", "typedef", "var", "void", "with", "true", "false", "null", "required"]
        default:
            control = []
            keywords = []
        }
        return (keywords, control)
    }

    private static func apply(patterns: [String], with painter: RenderingPainter, source: NSString, range: NSRange, options: NSRegularExpression.Options = [], attributes: [NSAttributedString.Key: Any]) {
        let text = source as String
        for pattern in patterns {
            guard let regex = regex(pattern, options: options) else { continue }
            regex.enumerateMatches(in: text, options: [], range: range) { match, _, _ in
                guard let match else { return }
                painter.paint(attributes, range: match.range)
            }
        }
    }

    private static func applyCaptureGroup(pattern: String, group: Int, with painter: RenderingPainter, source: NSString, range: NSRange, options: NSRegularExpression.Options = [], attributes: [NSAttributedString.Key: Any]) {
        guard let regex = regex(pattern, options: options) else { return }
        regex.enumerateMatches(in: source as String, options: [], range: range) { match, _, _ in
            guard let match, group < match.numberOfRanges else { return }
            let captured = match.range(at: group)
            guard captured.location != NSNotFound else { return }
            painter.paint(attributes, range: captured)
        }
    }
}
