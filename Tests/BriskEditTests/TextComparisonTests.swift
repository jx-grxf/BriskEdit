import XCTest
@testable import BriskEdit

final class TextComparisonTests: XCTestCase {
    func testDiffShowsBothVersionsWithoutChangingInput() throws {
        let diff = try TextComparisonService.unifiedDiff(original: "one\ntwo\n", updated: "one\nthree\n")
        XCTAssertTrue(diff.contains("--- Disk"))
        XCTAssertTrue(diff.contains("+++ Editor"))
        XCTAssertTrue(diff.contains("-two"))
        XCTAssertTrue(diff.contains("+three"))
    }

    func testEqualTextHasNoDiff() throws {
        XCTAssertEqual(try TextComparisonService.unifiedDiff(original: "ü\r\n", updated: "ü\r\n"), "")
    }

    func testMissingFinalNewlineIsVisible() throws {
        let diff = try TextComparisonService.unifiedDiff(original: "line\n", updated: "line")
        XCTAssertFalse(diff.isEmpty)
        XCTAssertTrue(diff.contains("No newline"))
    }

    func testDiskComparisonPreservesUTF16File() async throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: url) }
        try "Grüße\n".write(to: url, atomically: true, encoding: .utf16)
        let before = try Data(contentsOf: url)
        let result = try await TextComparisonService.compareWithDisk(file: url, text: "Hallo\n")
        XCTAssertTrue(result.contains("-Grüße"))
        XCTAssertTrue(result.contains("+Hallo"))
        XCTAssertEqual(try Data(contentsOf: url), before)
    }
}
