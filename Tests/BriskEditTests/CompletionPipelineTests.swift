import XCTest
@testable import BriskEdit

final class CompletionPipelineTests: XCTestCase {
    func testParsesReferenceLocations() {
        let result: [[String: Any]] = [
            ["uri": "file:///tmp/a.swift", "range": ["start": ["line": 2, "character": 4]]],
            ["uri": "file:///tmp/b.swift", "range": ["start": ["line": 0, "character": 0]]]
        ]

        XCTAssertEqual(LSPService.parseLocations(result), [
            LSPLocation(uri: "file:///tmp/a.swift", line: 3, column: 5),
            LSPLocation(uri: "file:///tmp/b.swift", line: 1, column: 1)
        ])
    }
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
