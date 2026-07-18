import XCTest
@testable import BriskEdit

final class CompletionPipelineTests: XCTestCase {
    func testPythonFallbackContainsPrintButNoCFunctions() {
        XCTAssertTrue(SourceLanguage.python.completionWords.contains("print"))
        XCTAssertFalse(SourceLanguage.python.completionWords.contains("printf"))
        XCTAssertFalse(SourceLanguage.python.completionWords.contains("scanf"))
        XCTAssertTrue(SourceLanguage.c.completionWords.contains("printf"))
    }

    func testLSPCompletionPreservesDisplayFilterAndInsertionText() {
        let result: [[String: Any]] = [[
            "label": "print(value)",
            "filterText": "print",
            "insertText": "print",
            "detail": "builtins",
            "kind": 3
        ]]

        XCTAssertEqual(LSPService.parseCompletions(result), [
            LSPCompletion(label: "print(value)", detail: "builtins", kind: 3,
                          insertionText: "print", filterText: "print")
        ])
    }

    func testLSPTextEditTakesPrecedenceOverInsertText() {
        let result: [[String: Any]] = [[
            "label": "member",
            "insertText": "wrong",
            "textEdit": [
                "range": [
                    "start": ["line": 0, "character": 0],
                    "end": ["line": 0, "character": 3]
                ],
                "newText": "member"
            ]
        ]]

        XCTAssertEqual(LSPService.parseCompletions(result).first?.insertionText, "member")
    }

    func testOverloadsAreNotCollapsedWhenDetailsDiffer() {
        let result: [[String: Any]] = [
            ["label": "open", "detail": "(file: str)", "kind": 3],
            ["label": "open", "detail": "(fd: int)", "kind": 3]
        ]

        XCTAssertEqual(LSPService.parseCompletions(result).count, 2)
    }
}
