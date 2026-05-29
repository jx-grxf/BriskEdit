import AppKit
import Foundation

enum SyntaxHighlighter {
    private static let maxHighlightedCharacters = 500_000

    @MainActor
    static func apply(to textView: NSTextView, language: SourceLanguage, theme: EditorTheme) {
        let contentStorage = textView.textContentStorage
        let storage = contentStorage?.textStorage ?? textView.textStorage
        let textLayoutManager = textView.textLayoutManager
        guard let storage else { return }
        let fullRange = NSRange(location: 0, length: storage.length)
        guard fullRange.length > 0 else { return }

        let applyAttributes = {
            let baseAttributes: [NSAttributedString.Key: Any] = [
                .font: theme.nsFont,
                .foregroundColor: theme.foreground,
                .paragraphStyle: theme.paragraphStyle
            ]
            storage.setAttributes(baseAttributes, range: fullRange)
            applyRenderingAttributes(baseAttributes, range: fullRange, textLayoutManager: textLayoutManager, replacingForeground: true)

            guard storage.length <= maxHighlightedCharacters, language != .plainText else {
                return
            }

            let source = storage.string as NSString
            let text = storage.string
            highlightKeywords(in: storage, source: source, language: language, color: theme.keyword, textLayoutManager: textLayoutManager)
            highlightNumbers(in: storage, source: source, color: theme.number, textLayoutManager: textLayoutManager)
            highlightStrings(in: storage, source: source, color: theme.string, textLayoutManager: textLayoutManager)
            highlightComments(in: storage, source: source, text: text, language: language, color: theme.comment, textLayoutManager: textLayoutManager)
        }

        if let contentStorage {
            contentStorage.performEditingTransaction(applyAttributes)
            if let textLayoutManager, !textLayoutManager.documentRange.isEmpty {
                textLayoutManager.invalidateRenderingAttributes(for: textLayoutManager.documentRange)
            }
        } else {
            storage.beginEditing()
            applyAttributes()
            storage.endEditing()
        }
        textView.needsDisplay = true
    }

    private static func highlightComments(
        in storage: NSTextStorage,
        source: NSString,
        text: String,
        language: SourceLanguage,
        color: NSColor,
        textLayoutManager: NSTextLayoutManager?
    ) {
        let patterns: [String]
        switch language {
        case .markdown:
            patterns = ["<!--(?s:.*?)-->"]
        case .python, .shell, .yaml:
            patterns = ["#.*$"]
        default:
            patterns = ["//.*$", "/\\*(?s:.*?)\\*/"]
        }

        apply(patterns: patterns, to: storage, source: source, options: [.anchorsMatchLines], textLayoutManager: textLayoutManager) {
            [.foregroundColor: color]
        }

        if language == .markdown {
            apply(patterns: ["^#{1,6}\\s+.*$"], to: storage, source: source, options: [.anchorsMatchLines], textLayoutManager: textLayoutManager) {
                [.foregroundColor: color, .font: NSFont.monospacedSystemFont(ofSize: 13, weight: .semibold)]
            }
        }
    }

    private static func highlightStrings(in storage: NSTextStorage, source: NSString, color: NSColor, textLayoutManager: NSTextLayoutManager?) {
        apply(patterns: ["\"(?:\\\\.|[^\"\\\\])*\"", "'(?:\\\\.|[^'\\\\])*'"], to: storage, source: source, textLayoutManager: textLayoutManager) {
            [.foregroundColor: color]
        }
    }

    private static func highlightNumbers(in storage: NSTextStorage, source: NSString, color: NSColor, textLayoutManager: NSTextLayoutManager?) {
        apply(patterns: ["\\b\\d+(?:\\.\\d+)?\\b"], to: storage, source: source, textLayoutManager: textLayoutManager) {
            [.foregroundColor: color]
        }
    }

    private static func highlightKeywords(
        in storage: NSTextStorage,
        source: NSString,
        language: SourceLanguage,
        color: NSColor,
        textLayoutManager: NSTextLayoutManager?
    ) {
        let words: [String]
        switch language {
        case .c, .cpp:
            words = ["auto", "break", "case", "char", "const", "continue", "default", "do", "double", "else", "enum", "extern", "float", "for", "if", "inline", "int", "long", "return", "short", "signed", "sizeof", "static", "struct", "switch", "typedef", "union", "unsigned", "void", "while", "class", "namespace", "template", "typename", "using"]
        case .swift:
            words = ["actor", "as", "async", "await", "case", "catch", "class", "enum", "extension", "false", "for", "func", "guard", "if", "import", "in", "let", "nil", "private", "protocol", "public", "return", "self", "static", "struct", "switch", "throws", "true", "try", "var", "while"]
        case .javascript, .typescript:
            words = ["async", "await", "break", "case", "catch", "class", "const", "continue", "default", "else", "export", "false", "for", "function", "if", "import", "let", "new", "null", "return", "switch", "this", "throw", "true", "try", "type", "var", "while"]
        case .python:
            words = ["and", "as", "async", "await", "break", "class", "continue", "def", "elif", "else", "except", "False", "for", "from", "if", "import", "in", "is", "lambda", "None", "not", "or", "pass", "return", "True", "try", "while", "with", "yield"]
        case .rust:
            words = ["as", "async", "await", "break", "const", "continue", "crate", "else", "enum", "false", "fn", "for", "if", "impl", "let", "loop", "match", "mod", "move", "mut", "pub", "ref", "return", "self", "struct", "trait", "true", "type", "use", "where", "while"]
        case .go:
            words = ["break", "case", "chan", "const", "continue", "default", "defer", "else", "fallthrough", "for", "func", "go", "goto", "if", "import", "interface", "map", "package", "range", "return", "select", "struct", "switch", "type", "var"]
        default:
            words = []
        }
        guard !words.isEmpty else { return }
        let escaped = words.map(NSRegularExpression.escapedPattern(for:)).joined(separator: "|")
        apply(patterns: ["\\b(\(escaped))\\b"], to: storage, source: source, textLayoutManager: textLayoutManager) {
            [.foregroundColor: color]
        }
    }

    private static func apply(
        patterns: [String],
        to storage: NSTextStorage,
        source: NSString,
        options: NSRegularExpression.Options = [],
        textLayoutManager: NSTextLayoutManager?,
        attributes: () -> [NSAttributedString.Key: Any]
    ) {
        for pattern in patterns {
            guard let regex = try? NSRegularExpression(pattern: pattern, options: options) else { continue }
            let range = NSRange(location: 0, length: source.length)
            regex.enumerateMatches(in: source as String, options: [], range: range) { match, _, _ in
                guard let match else { return }
                let attrs = attributes()
                storage.addAttributes(attrs, range: match.range)
                applyRenderingAttributes(attrs, range: match.range, textLayoutManager: textLayoutManager)
            }
        }
    }

    private static func applyRenderingAttributes(
        _ attributes: [NSAttributedString.Key: Any],
        range: NSRange,
        textLayoutManager: NSTextLayoutManager?,
        replacingForeground: Bool = false
    ) {
        guard
            let textLayoutManager,
            !textLayoutManager.documentRange.isEmpty,
            let textRange = textLayoutManager.textContentManager?.textRange(for: range)
        else { return }

        if replacingForeground {
            textLayoutManager.removeRenderingAttribute(.foregroundColor, for: textLayoutManager.documentRange)
        }

        for (key, value) in attributes {
            textLayoutManager.addRenderingAttribute(key, value: value, for: textRange)
        }
    }
}

private extension NSTextElementProvider {
    func textRange(for range: NSRange) -> NSTextRange? {
        guard
            let start = location?(documentRange.location, offsetBy: range.location),
            let end = location?(start, offsetBy: range.length)
        else { return nil }

        return NSTextRange(location: start, end: end)
    }
}
