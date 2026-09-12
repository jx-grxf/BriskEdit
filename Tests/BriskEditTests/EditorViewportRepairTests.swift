import XCTest
@testable import BriskEdit

final class EditorViewportRepairTests: XCTestCase {
    private func needsRelayout(
        width: CGFloat = 800,
        height: CGFloat = 600,
        laidOutHeight: CGFloat = 4_000,
        hasText: Bool = true,
        showsLaidOutText: Bool = true
    ) -> Bool {
        EditorViewportRepairPolicy.needsRelayout(
            viewportWidth: width,
            viewportHeight: height,
            laidOutHeight: laidOutHeight,
            hasText: hasText,
            showsLaidOutText: showsLaidOutText
        )
    }

    func testMeasuredViewportWithUnlaidTextIsRepaired() {
        // The editor was built while its container had no height: the document
        // has text but nothing was ever laid out.
        XCTAssertTrue(needsRelayout(laidOutHeight: 0, showsLaidOutText: false))
    }

    func testViewportPastTheContentIsRepaired() {
        XCTAssertTrue(needsRelayout(showsLaidOutText: false))
    }

    func testUnmeasuredViewportWaitsForItsLayoutPass() {
        XCTAssertFalse(needsRelayout(height: 0, laidOutHeight: 0, showsLaidOutText: false))
        XCTAssertFalse(needsRelayout(width: 0, laidOutHeight: 0, showsLaidOutText: false))
    }

    func testEmptyDocumentIsNotARepairCase() {
        XCTAssertFalse(needsRelayout(laidOutHeight: 0, hasText: false, showsLaidOutText: false))
    }

    func testVisibleTextIsLeftAlone() {
        XCTAssertFalse(needsRelayout())
    }
}
