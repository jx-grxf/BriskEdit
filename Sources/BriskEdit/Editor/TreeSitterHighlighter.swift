import AppKit
import Neon
import SwiftTreeSitter
import TreeSitterJSON
import TreeSitterSwift

@MainActor
final class TreeSitterHighlighter {
    private final class ThemeBox {
        var theme: EditorTheme

        init(theme: EditorTheme) {
            self.theme = theme
        }
    }

    let language: SourceLanguage

    private let highlighter: TextViewHighlighter
    private let themeBox: ThemeBox

    init(textView: NSTextView, language: SourceLanguage, theme: EditorTheme) throws {
        guard Self.supports(language) else {
            throw TreeSitterHighlighterError.unsupportedLanguage
        }

        let configuration = try Self.languageConfiguration(for: language)
        guard configuration.queries[.highlights] != nil else {
            throw TreeSitterHighlighterError.missingHighlightQuery
        }

        let themeBox = ThemeBox(theme: theme)
        let attributeProvider: TokenAttributeProvider = { [themeBox] token in
            Self.attributes(for: token.name, theme: themeBox.theme)
        }
        let highlighterConfiguration = TextViewHighlighter.Configuration(
            languageConfiguration: configuration,
            attributeProvider: attributeProvider,
            locationTransformer: { _ in nil }
        )

        self.language = language
        self.themeBox = themeBox
        self.highlighter = try TextViewHighlighter(
            textView: textView,
            configuration: highlighterConfiguration
        )
    }

    static func supports(_ language: SourceLanguage) -> Bool {
        language == .swift || language == .json
    }

    func updateTheme(_ theme: EditorTheme) {
        guard themeBox.theme != theme else { return }
        themeBox.theme = theme
        highlighter.invalidate(.all)
    }

    func invalidate() {
        highlighter.invalidate(.all)
    }

    static func attributes(for tokenName: String, theme: EditorTheme) -> [NSAttributedString.Key: Any] {
        guard let color = color(for: tokenName, theme: theme) else { return [:] }
        return [.foregroundColor: color]
    }

    private static func color(for tokenName: String, theme: EditorTheme) -> NSColor? {
        if tokenName.hasPrefix("comment") || tokenName == "spell" {
            return theme.comment
        }
        if tokenName.hasPrefix("string") || tokenName == "escape" {
            return theme.string
        }
        if tokenName.hasPrefix("number") || tokenName.hasPrefix("constant") || tokenName == "boolean" {
            return theme.number
        }
        if tokenName.hasPrefix("keyword.conditional") ||
            tokenName.hasPrefix("keyword.repeat") ||
            tokenName.hasPrefix("keyword.return") ||
            tokenName.hasPrefix("keyword.exception") {
            return theme.controlKeyword
        }
        if tokenName.hasPrefix("keyword") {
            return theme.keyword
        }
        if tokenName.hasPrefix("attribute") || tokenName.hasPrefix("function.macro") {
            return theme.preprocessor
        }
        if tokenName.hasPrefix("function") || tokenName == "constructor" {
            return theme.function
        }
        if tokenName.hasPrefix("type") {
            return theme.type
        }
        return nil
    }

    private static func languageConfiguration(for language: SourceLanguage) throws -> LanguageConfiguration {
        switch language {
        case .swift:
            return try LanguageConfiguration(tree_sitter_swift(), name: "Swift")
        case .json:
            return try LanguageConfiguration(tree_sitter_json(), name: "JSON")
        default:
            throw TreeSitterHighlighterError.unsupportedLanguage
        }
    }
}

private enum TreeSitterHighlighterError: Error {
    case unsupportedLanguage
    case missingHighlightQuery
}
