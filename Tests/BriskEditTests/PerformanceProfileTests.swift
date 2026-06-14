import XCTest
@testable import BriskEdit

@MainActor
final class PerformanceProfileTests: XCTestCase {
    func testLowPowerProfileReducesLiveWork() {
        let profile = Preferences.PerformanceProfile(mode: .lowPower)

        XCTAssertFalse(profile.allowsMinimap)
        XCTAssertFalse(profile.allowsHover)
        XCTAssertTrue(profile.reduceMotion)
        XCTAssertGreaterThan(profile.highlightDebounce, 0.08)
        XCTAssertGreaterThan(profile.gitDiffDebounce, 0.4)
        XCTAssertGreaterThan(profile.markdownPreviewDebounceMilliseconds, 180)
    }

    func testPowerProfileKeepsLiveFeaturesImmediate() {
        let profile = Preferences.PerformanceProfile(mode: .power)

        XCTAssertTrue(profile.allowsMinimap)
        XCTAssertTrue(profile.allowsHover)
        XCTAssertFalse(profile.reduceMotion)
        XCTAssertEqual(profile.highlightDebounce, 0.08)
        XCTAssertEqual(profile.gitDiffDebounce, 0.4)
        XCTAssertEqual(profile.markdownPreviewDebounceMilliseconds, 180)
    }
}
