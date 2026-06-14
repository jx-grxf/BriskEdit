import AppKit
import XCTest
@testable import BriskEdit

final class TreeSitterHighlighterTests: XCTestCase {
    @MainActor
    func testOnlySwiftAndJSONUseTreeSitter() {
        XCTAssertTrue(TreeSitterHighlighter.supports(.swift))
        XCTAssertTrue(TreeSitterHighlighter.supports(.json))
        XCTAssertFalse(TreeSitterHighlighter.supports(.python))
        XCTAssertFalse(TreeSitterHighlighter.supports(.plainText))
    }

    @MainActor
    func testTokenCategoriesMapToCurrentTheme() {
        let theme = EditorTheme.default

        XCTAssertEqual(
            TreeSitterHighlighter.attributes(for: "keyword.conditional", theme: theme)[.foregroundColor] as? NSColor,
            theme.controlKeyword
        )
        XCTAssertEqual(
            TreeSitterHighlighter.attributes(for: "function.call", theme: theme)[.foregroundColor] as? NSColor,
            theme.function
        )
        XCTAssertEqual(
            TreeSitterHighlighter.attributes(for: "string.special.key", theme: theme)[.foregroundColor] as? NSColor,
            theme.string
        )
        XCTAssertEqual(
            TreeSitterHighlighter.attributes(for: "function.macro", theme: theme)[.foregroundColor] as? NSColor,
            theme.preprocessor
        )
        XCTAssertTrue(TreeSitterHighlighter.attributes(for: "punctuation.bracket", theme: theme).isEmpty)
    }

    @MainActor
    func testSwiftAndJSONHighlightersInitializeOnTextKit2() throws {
        let (swiftView, swiftScrollView) = makeTextView(text: "let value = 1")
        let (jsonView, jsonScrollView) = makeTextView(text: "{\"value\": 1}")

        let swiftHighlighter = try TreeSitterHighlighter(
            textView: swiftView,
            language: .swift,
            theme: .default
        )
        let jsonHighlighter = try TreeSitterHighlighter(
            textView: jsonView,
            language: .json,
            theme: .default
        )

        withExtendedLifetime((swiftHighlighter, jsonHighlighter, swiftScrollView, jsonScrollView)) {}
    }

    @MainActor
    private func makeTextView(text: String) -> (NSTextView, NSScrollView) {
        let textView = NSTextView(usingTextLayoutManager: true)
        textView.string = text
        let scrollView = NSScrollView()
        scrollView.documentView = textView
        return (textView, scrollView)
    }
}
