import AppKit
import SwiftUI

struct TextKit2EditorHost: NSViewRepresentable {
    @Bindable var document: TextDocument
    let theme: EditorTheme

    func makeNSView(context: Context) -> NSScrollView {
        let textView = NSTextView(usingTextLayoutManager: true)
        textView.delegate = context.coordinator
        textView.string = document.text
        configure(textView, theme: theme)
        context.coordinator.textView = textView
        context.coordinator.document = document
        context.coordinator.theme = theme

        let scrollView = NSScrollView()
        scrollView.borderType = .noBorder
        scrollView.drawsBackground = true
        scrollView.backgroundColor = theme.background
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true
        scrollView.documentView = textView

        textView.minSize = .zero
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        textView.isHorizontallyResizable = false
        textView.isVerticallyResizable = true
        textView.autoresizingMask = [.width]
        textView.textContainer?.widthTracksTextView = true
        textView.textContainer?.heightTracksTextView = false
        textView.textContainer?.containerSize = NSSize(width: scrollView.contentSize.width, height: CGFloat.greatestFiniteMagnitude)

        context.coordinator.applyHighlight()
        DispatchQueue.main.async { [weak scrollView, weak textView] in
            scrollView?.window?.makeFirstResponder(textView)
        }
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let textView = context.coordinator.textView else { return }
        context.coordinator.document = document
        context.coordinator.theme = theme

        configure(textView, theme: theme)
        if textView.string != document.text {
            let selection = textView.selectedRange()
            textView.string = document.text
            textView.setSelectedRange(NSRange(location: min(selection.location, (document.text as NSString).length), length: 0))
        }
        context.coordinator.applyHighlight()
        scrollView.backgroundColor = theme.background
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(document: document, theme: theme)
    }

    private func configure(_ textView: NSTextView, theme: EditorTheme) {
        textView.isEditable = true
        textView.isSelectable = true
        textView.isRichText = false
        textView.importsGraphics = false
        textView.allowsUndo = true
        textView.drawsBackground = true
        textView.backgroundColor = theme.background
        textView.textColor = theme.foreground
        textView.insertionPointColor = theme.cursor
        textView.font = theme.nsFont
        textView.defaultParagraphStyle = theme.paragraphStyle
        textView.typingAttributes = [
            .font: theme.nsFont,
            .foregroundColor: theme.foreground,
            .paragraphStyle: theme.paragraphStyle
        ]
        textView.textContainerInset = NSSize(width: 8, height: 8)
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        textView.isAutomaticSpellingCorrectionEnabled = false
        textView.smartInsertDeleteEnabled = false
        textView.usesFindBar = true
        textView.isIncrementalSearchingEnabled = true
    }

    @MainActor
    final class Coordinator: NSObject, NSTextViewDelegate {
        var document: TextDocument
        var theme: EditorTheme
        weak var textView: NSTextView?
        private var highlightWork: DispatchWorkItem?

        init(document: TextDocument, theme: EditorTheme) {
            self.document = document
            self.theme = theme
        }

        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            document.applyEdit(text: textView.string)
            scheduleHighlight()
        }

        func textViewDidChangeSelection(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            document.updateCursor(location: textView.selectedRange().location)
        }

        func textView(_ textView: NSTextView, completions words: [String], forPartialWordRange charRange: NSRange, indexOfSelectedItem index: UnsafeMutablePointer<Int>?) -> [String] {
            let partial = (textView.string as NSString).substring(with: charRange).lowercased()
            let baseWords = Set(document.language.completionWords + globalCompletionWords + words)
            let matches = baseWords
                .filter { partial.isEmpty || $0.lowercased().hasPrefix(partial) }
                .sorted { $0.localizedStandardCompare($1) == .orderedAscending }
            index?.pointee = 0
            return Array(matches.prefix(80))
        }

        func textView(_ textView: NSTextView, shouldChangeTextIn range: NSRange, replacementString: String?) -> Bool {
            guard let string = replacementString, range.length == 0, string.count == 1 else { return true }
            let pairs: [Character: Character] = ["{": "}", "(": ")", "[": "]", "\"": "\"", "'": "'"]
            guard let opener = string.first, let closer = pairs[opener] else { return true }
            textView.insertText("\(opener)\(closer)", replacementRange: range)
            textView.setSelectedRange(NSRange(location: range.location + 1, length: 0))
            return false
        }

        func textView(_ textView: NSTextView, doCommandBy selector: Selector) -> Bool {
            switch selector {
            case #selector(NSResponder.insertTab(_:)):
                textView.insertText(indentUnit, replacementRange: textView.selectedRange())
                return true
            case #selector(NSResponder.insertNewline(_:)):
                insertSmartNewline(in: textView)
                return true
            case #selector(NSResponder.complete(_:)):
                textView.complete(nil)
                return true
            default:
                return false
            }
        }

        func applyHighlight() {
            guard let textView else { return }
            TextKit2SyntaxHighlighter.apply(to: textView, language: document.language, theme: theme)
        }

        private func scheduleHighlight() {
            highlightWork?.cancel()
            let work = DispatchWorkItem { [weak self] in
                self?.applyHighlight()
            }
            highlightWork = work
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.08, execute: work)
        }

        private var indentUnit: String {
            theme.usesSpacesForTabs ? String(repeating: " ", count: theme.tabWidth) : "\t"
        }

        private let globalCompletionWords = [
            "TODO:", "MARK:", "FIXME:", "main", "print", "return", "true", "false", "null", "nil"
        ]

        private func insertSmartNewline(in textView: NSTextView) {
            let nsString = textView.string as NSString
            let selection = textView.selectedRange()
            let lineStart = nsString.lineRange(for: NSRange(location: selection.location, length: 0)).location
            var offset = lineStart
            var indent = ""
            while offset < selection.location {
                guard let scalar = UnicodeScalar(nsString.character(at: offset)), scalar == " " || scalar == "\t" else { break }
                indent.append(Character(scalar))
                offset += 1
            }

            var insertion = "\n" + indent
            if selection.location > 0, let previous = UnicodeScalar(nsString.character(at: selection.location - 1)), previous == "{" || previous == "(" || previous == "[" || previous == ":" {
                insertion += indentUnit
            }
            textView.insertText(insertion, replacementRange: selection)
        }
    }
}

private enum TextKit2SyntaxHighlighter {
    private static let maxHighlightedCharacters = 500_000

    @MainActor
    static func apply(to textView: NSTextView, language: SourceLanguage, theme: EditorTheme) {
        guard let contentStorage = textView.textContentStorage, let storage = contentStorage.textStorage else { return }
        let fullRange = NSRange(location: 0, length: storage.length)
        guard fullRange.length > 0 else {
            textView.typingAttributes = baseAttributes(theme: theme)
            return
        }

        contentStorage.performEditingTransaction {
            storage.setAttributes(baseAttributes(theme: theme), range: fullRange)
            guard storage.length <= maxHighlightedCharacters, language != .plainText else { return }

            let source = storage.string as NSString
            highlightComments(in: storage, source: source, language: language, color: theme.comment)
            highlightStrings(in: storage, source: source, color: theme.string)
            highlightNumbers(in: storage, source: source, color: theme.number)
            highlightKeywords(in: storage, source: source, language: language, color: theme.keyword)
            highlightPreprocessor(in: storage, source: source, language: language, color: NSColor.systemPink)
        }
        textView.typingAttributes = baseAttributes(theme: theme)
        textView.needsDisplay = true
    }

    private static func baseAttributes(theme: EditorTheme) -> [NSAttributedString.Key: Any] {
        [
            .font: theme.nsFont,
            .foregroundColor: theme.foreground,
            .paragraphStyle: theme.paragraphStyle
        ]
    }

    private static func highlightComments(in storage: NSTextStorage, source: NSString, language: SourceLanguage, color: NSColor) {
        let patterns: [String]
        switch language {
        case .markdown:
            patterns = ["<!--(?s:.*?)-->"]
        case .python, .shell, .yaml:
            patterns = ["#.*$"]
        default:
            patterns = ["//.*$", "/\\*(?s:.*?)\\*/"]
        }
        apply(patterns: patterns, to: storage, source: source, options: [.anchorsMatchLines], attributes: [.foregroundColor: color])
    }

    private static func highlightStrings(in storage: NSTextStorage, source: NSString, color: NSColor) {
        apply(patterns: ["\"(?:\\\\.|[^\"\\\\])*\"", "'(?:\\\\.|[^'\\\\])*'"], to: storage, source: source, attributes: [.foregroundColor: color])
    }

    private static func highlightNumbers(in storage: NSTextStorage, source: NSString, color: NSColor) {
        apply(patterns: ["\\b\\d+(?:\\.\\d+)?\\b"], to: storage, source: source, attributes: [.foregroundColor: color])
    }

    private static func highlightPreprocessor(in storage: NSTextStorage, source: NSString, language: SourceLanguage, color: NSColor) {
        guard language == .c || language == .cpp else { return }
        apply(
            patterns: ["^\\s*#\\s*(include|define|if|ifdef|ifndef|else|elif|endif|pragma|undef|error|warning)\\b.*$"],
            to: storage,
            source: source,
            options: [.anchorsMatchLines],
            attributes: [.foregroundColor: color]
        )
    }

    private static func highlightKeywords(in storage: NSTextStorage, source: NSString, language: SourceLanguage, color: NSColor) {
        let words: [String]
        switch language {
        case .c, .cpp:
            words = ["auto", "break", "case", "char", "const", "continue", "default", "do", "double", "else", "enum", "extern", "float", "for", "if", "inline", "int", "long", "return", "short", "signed", "sizeof", "static", "struct", "switch", "typedef", "union", "unsigned", "void", "while", "class", "namespace", "template", "typename", "using"]
        case .swift:
            words = ["actor", "as", "async", "await", "case", "catch", "class", "enum", "extension", "false", "for", "func", "guard", "if", "import", "in", "let", "nil", "private", "protocol", "public", "return", "self", "static", "struct", "switch", "throws", "true", "try", "var", "while"]
        case .javascript, .typescript:
            words = ["async", "await", "break", "case", "catch", "class", "const", "continue", "default", "else", "export", "false", "for", "function", "if", "import", "let", "new", "null", "return", "switch", "this", "throw", "true", "try", "type", "var", "while"]
        case .php:
            words = ["abstract", "array", "class", "const", "echo", "else", "elseif", "extends", "false", "for", "foreach", "function", "if", "implements", "interface", "namespace", "new", "null", "private", "protected", "public", "return", "static", "true", "use", "var", "while"]
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
        apply(patterns: ["\\b(\(escaped))\\b"], to: storage, source: source, attributes: [.foregroundColor: color])
    }

    private static func apply(patterns: [String], to storage: NSTextStorage, source: NSString, options: NSRegularExpression.Options = [], attributes: [NSAttributedString.Key: Any]) {
        for pattern in patterns {
            guard let regex = try? NSRegularExpression(pattern: pattern, options: options) else { continue }
            regex.enumerateMatches(in: source as String, options: [], range: NSRange(location: 0, length: source.length)) { match, _, _ in
                guard let match else { return }
                storage.addAttributes(attributes, range: match.range)
            }
        }
    }
}
