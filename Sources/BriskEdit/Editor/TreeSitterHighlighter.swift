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

    // Compiling the tree-sitter query for a grammar is expensive — the Swift
    // highlights query costs ~1.5s with `ts_query_new`. We rebuild a highlighter
    // on every file open and tab switch, so the compiled `LanguageConfiguration`
    // (which is `Sendable`/immutable) is cached and reused across instances.
    private static var configurationCache: [SourceLanguage: LanguageConfiguration] = [:]
    private static var inFlightCompiles: [SourceLanguage: Task<LanguageConfiguration?, Never>] = [:]

    /// Returns the already-compiled config for `language`, or nil if it hasn't
    /// been compiled yet (callers should fall back and call `prepareConfiguration`).
    static func cachedConfiguration(for language: SourceLanguage) -> LanguageConfiguration? {
        configurationCache[language]
    }

    /// Compiles (off the main thread) and caches the config for `language`,
    /// de-duplicating concurrent requests. Returns nil for unsupported grammars
    /// or on failure.
    @discardableResult
    static func prepareConfiguration(for language: SourceLanguage) async -> LanguageConfiguration? {
        if let cached = configurationCache[language] { return cached }
        let task: Task<LanguageConfiguration?, Never>
        if let existing = inFlightCompiles[language] {
            task = existing
        } else {
            task = Task<LanguageConfiguration?, Never>.detached(priority: .userInitiated) {
                try? Self.compileConfiguration(for: language)
            }
            inFlightCompiles[language] = task
        }
        let config = await task.value
        // Every awaiter writes through to the cache (not just the task's original
        // owner), so the moment any `prepare` returns non-nil the synchronous
        // `cachedConfiguration` lookup is guaranteed to see it.
        inFlightCompiles[language] = nil
        if let config { configurationCache[language] = config }
        return config
    }

    /// Warms the heavy grammars in the background so the first open doesn't pay
    /// the ~1.5s query-compile cost on the main thread. Compiles **one grammar at
    /// a time** (low priority) so the pre-warm itself never makes the UI stutter.
    static func warmUp(_ languages: [SourceLanguage] = [.swift, .json]) {
        Task(priority: .utility) {
            for language in languages where supports(language) {
                await prepareConfiguration(for: language)
            }
        }
    }

    init(textView: NSTextView, language: SourceLanguage, configuration: LanguageConfiguration, theme: EditorTheme) throws {
        guard Self.supports(language) else {
            throw TreeSitterHighlighterError.unsupportedLanguage
        }

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

    /// Pure C grammar loading + query compilation — safe to run off the main
    /// thread (no shared mutable state; the result is `Sendable`).
    nonisolated private static func compileConfiguration(for language: SourceLanguage) throws -> LanguageConfiguration {
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
