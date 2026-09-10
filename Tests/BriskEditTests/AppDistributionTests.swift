import XCTest
@testable import BriskEdit

final class AppDistributionTests: XCTestCase {
    func testMissingOrUnknownMarkerMeansRelease() {
        XCTAssertEqual(AppDistribution(infoDictionary: nil), .release)
        XCTAssertEqual(AppDistribution(infoDictionary: ["BriskEditDistribution": "canary"]), .release)
    }

    func testNightlyMarkerSelectsNightly() {
        XCTAssertEqual(AppDistribution(infoDictionary: ["BriskEditDistribution": "nightly"]), .nightly)
    }

    func testNightlyNeverSharesReleaseStateOrCommands() {
        XCTAssertNotEqual(AppDistribution.nightly.supportDirectoryName, AppDistribution.release.supportDirectoryName)
        XCTAssertEqual(AppDistribution.release.cliCommandNames.primary, "briskedit")
        XCTAssertEqual(AppDistribution.release.cliCommandNames.alias, "brisk")
        XCTAssertEqual(AppDistribution.nightly.cliCommandNames.primary, "briskedit-nightly")
        XCTAssertEqual(AppDistribution.nightly.cliCommandNames.alias, "brisk-nightly")
    }

    func testNightlyDoesNotAnnounceWhatsNew() {
        XCTAssertNil(WhatsNew.versionToAnnounceAndMarkSeen(distribution: .nightly))
    }
}
