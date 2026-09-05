import XCTest
@testable import BriskEdit

final class GitDiffTextTests: XCTestCase {
    func testSeparatesStagedAndUnstagedDiffs() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("briskedit-git-diff-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let file = root.appendingPathComponent("sample.txt")
        try "one\n".write(to: file, atomically: true, encoding: .utf8)
        try runGit(["init", "-q"], at: root)
        try runGit(["config", "user.name", "BriskEdit Tests"], at: root)
        try runGit(["config", "user.email", "tests@example.invalid"], at: root)
        try runGit(["add", "sample.txt"], at: root)
        try runGit(["commit", "-qm", "Initial"], at: root)

        try "one\ntwo\n".write(to: file, atomically: true, encoding: .utf8)
        try runGit(["add", "sample.txt"], at: root)
        try "one\ntwo\nthree\n".write(to: file, atomically: true, encoding: .utf8)

        let staged = try await GitService.diffText(for: file, root: root, staged: true)
        let unstaged = try await GitService.diffText(for: file, root: root, staged: false)
        XCTAssertTrue(staged.contains("+two"))
        XCTAssertFalse(staged.contains("+three"))
        XCTAssertTrue(unstaged.contains("+three"))
    }

    private func runGit(_ arguments: [String], at root: URL) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        process.arguments = ["-C", root.path] + arguments
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try process.run()
        process.waitUntilExit()
        XCTAssertEqual(process.terminationStatus, 0)
    }
}
