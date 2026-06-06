import AppKit
import XCTest
@testable import BriskEdit

@MainActor
final class EditorFormatRequestTests: XCTestCase {
    func testFormatShortcutIgnoresKeyRepeat() throws {
        let textView = BriskCodeTextView(usingTextLayoutManager: true)
        var requestCount = 0
        textView.canFormatDocument = { true }
        textView.onFormatDocument = { requestCount += 1 }

        let repeatedEvent = try XCTUnwrap(makeFormatEvent(isARepeat: true))

        XCTAssertFalse(textView.performKeyEquivalent(with: repeatedEvent))
        XCTAssertEqual(requestCount, 0)
    }

    func testFormatShortcutHandlesInitialKeyPress() throws {
        let textView = BriskCodeTextView(usingTextLayoutManager: true)
        var requestCount = 0
        textView.canFormatDocument = { true }
        textView.onFormatDocument = { requestCount += 1 }

        let event = try XCTUnwrap(makeFormatEvent(isARepeat: false))

        XCTAssertTrue(textView.performKeyEquivalent(with: event))
        XCTAssertEqual(requestCount, 1)
    }

    private func makeFormatEvent(isARepeat: Bool) -> NSEvent? {
        NSEvent.keyEvent(
            with: .keyDown,
            location: .zero,
            modifierFlags: [.shift, .option],
            timestamp: 0,
            windowNumber: 0,
            context: nil,
            characters: "F",
            charactersIgnoringModifiers: "f",
            isARepeat: isARepeat,
            keyCode: 3
        )
    }
}
