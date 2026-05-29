import XCTest
@testable import BriskEdit

final class SnippetExpanderTests: XCTestCase {
    func testExpandsPlaceholderAndPreservesIndentedContinuationLines() {
        let snippet = CodeSnippet(
            trigger: "if",
            detail: "if statement",
            body: "if ($1{condition}) {\n\t$0\n}"
        )

        let expanded = SnippetExpander.expand(snippet, baseIndent: "    ", indentUnit: "  ")

        XCTAssertEqual(expanded.text, "if (condition) {\n      \n    }")
        XCTAssertEqual(expanded.selection, NSRange(location: 4, length: 9))
    }

    func testFallsBackToCaretMarkerWhenNoPlaceholderExists() {
        let snippet = CodeSnippet(trigger: "main", detail: "main", body: "int main() {\n\t$0\n}")

        let expanded = SnippetExpander.expand(snippet, baseIndent: "", indentUnit: "    ")

        XCTAssertEqual(expanded.text, "int main() {\n    \n}")
        XCTAssertEqual(expanded.selection, NSRange(location: 17, length: 0))
    }
}
