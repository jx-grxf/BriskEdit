import Foundation
import XCTest
@testable import BriskEdit

final class GitPorcelainTests: XCTestCase {
    func testParsesUnicodeWhitespaceAndNewlinesVerbatim() {
        let data = Data("?? über file.swift\0 M folder/a\tb\nfile.txt\0".utf8)

        XCTAssertEqual(GitService.parsePorcelainV1Z(data), [
            .init(index: "?", worktree: "?", path: "über file.swift"),
            .init(index: " ", worktree: "M", path: "folder/a\tb\nfile.txt"),
        ])
    }

    func testRenameUsesDestinationAndSkipsOriginalPath() {
        let data = Data("R  new name.swift\0old name.swift\0?? other.swift\0".utf8)

        XCTAssertEqual(GitService.parsePorcelainV1Z(data), [
            .init(index: "R", worktree: " ", path: "new name.swift"),
            .init(index: "?", worktree: "?", path: "other.swift"),
        ])
    }
}
