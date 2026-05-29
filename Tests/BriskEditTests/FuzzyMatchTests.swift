import XCTest
@testable import BriskEdit

final class FuzzyMatchTests: XCTestCase {
    func testScoresSegmentBoundariesHigher() {
        let query = Array("wm")

        let segmentScore = FuzzyMatch.score(query: query, candidate: "Sources/w/m.swift")
        let inlineScore = FuzzyMatch.score(query: query, candidate: "Sources/warm.swift")

        XCTAssertNotNil(segmentScore)
        XCTAssertNotNil(inlineScore)
        XCTAssertGreaterThan(segmentScore ?? 0, inlineScore ?? 0)
    }

    func testReturnsNilWhenQueryIsNotASubsequence() {
        XCTAssertNil(FuzzyMatch.score(query: Array("xyz"), candidate: "WorkspaceModel.swift"))
    }

    func testMatchingIsCaseInsensitive() {
        XCTAssertNotNil(FuzzyMatch.score(query: Array("wm"), candidate: "WorkspaceModel.swift"))
    }
}
