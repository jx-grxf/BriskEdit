import XCTest
@testable import BriskEdit

@MainActor
final class RecentWorkspacesStoreTests: XCTestCase {

    func testRealFolderIsEligible() {
        let home = URL(fileURLWithPath: NSHomeDirectory(), isDirectory: true)
        XCTAssertTrue(RecentWorkspacesStore.isEligible(home))
        XCTAssertTrue(RecentWorkspacesStore.isEligible(home.appendingPathComponent("Projects/Demo")))
    }

    func testTemporaryDirectoriesAreNotEligible() {
        // The exact shape that leaked into Recent: a per-test temp workspace.
        let temp = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        XCTAssertFalse(RecentWorkspacesStore.isEligible(temp), "Temp fixtures must never be remembered")

        XCTAssertFalse(RecentWorkspacesStore.isEligible(URL(fileURLWithPath: "/var/folders/t4/abc/T/\(UUID().uuidString)")))
        XCTAssertFalse(RecentWorkspacesStore.isEligible(URL(fileURLWithPath: "/private/var/folders/t4/abc/T/x")))
        XCTAssertFalse(RecentWorkspacesStore.isEligible(URL(fileURLWithPath: "/tmp/scratch")))
    }
}
