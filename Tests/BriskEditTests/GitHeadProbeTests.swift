import XCTest
@testable import BriskEdit

final class GitHeadProbeTests: XCTestCase {
    func testBranchReference() {
        XCTAssertEqual(GitHeadProbe.branchName(fromHEAD: "ref: refs/heads/dev\n"), "dev")
        XCTAssertEqual(GitHeadProbe.branchName(fromHEAD: "ref: refs/heads/feat/nightly-ui\n"), "feat/nightly-ui")
    }

    func testDetachedHeadShowsItsShortCommit() {
        let commit = "271302a49d1a750eca264055ae80bc62c35e01af"
        XCTAssertEqual(GitHeadProbe.branchName(fromHEAD: commit + "\n"), "271302a")
    }

    func testNonBranchReferencesAndNoiseHaveNoLabel() {
        XCTAssertNil(GitHeadProbe.branchName(fromHEAD: "ref: refs/tags/v0.6.1\n"))
        XCTAssertNil(GitHeadProbe.branchName(fromHEAD: "ref: \n"))
        XCTAssertNil(GitHeadProbe.branchName(fromHEAD: "\n"))
        XCTAssertNil(GitHeadProbe.branchName(fromHEAD: "not a head file"))
        XCTAssertNil(GitHeadProbe.branchName(fromHEAD: "abc123"))
    }

    func testWorktreePointer() {
        XCTAssertEqual(
            GitHeadProbe.gitDirectory(fromPointer: "gitdir: /Users/x/repo/.git/worktrees/feature\n"),
            "/Users/x/repo/.git/worktrees/feature"
        )
        XCTAssertEqual(GitHeadProbe.gitDirectory(fromPointer: "gitdir: ../.git/modules/vendor\n"), "../.git/modules/vendor")
        XCTAssertNil(GitHeadProbe.gitDirectory(fromPointer: "gitdir:\n"))
        XCTAssertNil(GitHeadProbe.gitDirectory(fromPointer: "ref: refs/heads/main\n"))
    }

    func testBranchOfThisRepositoryOrNilOutsideOne() {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        // The checkout this test runs from is a repository; /usr never is.
        XCTAssertNotNil(GitHeadProbe.branch(at: root))
        XCTAssertNil(GitHeadProbe.branch(at: URL(fileURLWithPath: "/usr")))
    }
}
