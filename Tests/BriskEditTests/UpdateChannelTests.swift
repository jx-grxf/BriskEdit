import XCTest
@testable import BriskEdit

final class UpdateChannelTests: XCTestCase {
    func testBetaBinaryDefaultsToBetaChannelWithoutPreference() {
        XCTAssertEqual(UpdateService.initialChannel(storedValue: nil, bundleVersion: "0.6.0-beta.2"), .beta)
    }

    func testStoredPreferenceOverridesBinaryFlavor() {
        XCTAssertEqual(UpdateService.initialChannel(storedValue: "stable", bundleVersion: "0.6.0-beta.2"), .stable)
        XCTAssertEqual(UpdateService.initialChannel(storedValue: "beta", bundleVersion: "0.6.0"), .beta)
    }
}
