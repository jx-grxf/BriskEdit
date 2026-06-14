import XCTest
@testable import BriskEdit

@MainActor
final class CLIInstallerTests: XCTestCase {
    func testLauncherScriptOpensViaBundleIdentifier() {
        let script = CLIInstaller.launcherScript
        XCTAssertTrue(script.contains(#"open -b "$bundle_id""#))
        XCTAssertTrue(script.contains("com.johannesgrof.briskedit"))
    }

    func testLauncherScriptResolvesRelativeArgumentsToAbsolutePaths() {
        let script = CLIInstaller.launcherScript
        // cd into each argument's directory + `pwd` yields an absolute path, so
        // `briskedit .` and relative paths work from any working directory.
        XCTAssertTrue(script.contains(#"cd "$(dirname "$arg")""#))
        XCTAssertTrue(script.contains("pwd"))
    }

    func testLauncherScriptHandlesNoArguments() {
        XCTAssertTrue(CLIInstaller.launcherScript.contains(#"if [ "$#" -eq 0 ]"#))
    }

    func testLauncherScriptLivesUnderApplicationSupport() {
        XCTAssertEqual(CLIInstaller.launcherScriptURL.lastPathComponent, "briskedit")
        XCTAssertTrue(CLIInstaller.launcherScriptURL.path.contains("Application Support/BriskEdit"))
    }

    func testInstallerDoesNotReplaceForeignCommands() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let command = directory.appendingPathComponent("briskedit")
        try "foreign".write(to: command, atomically: true, encoding: .utf8)

        XCTAssertFalse(CLIInstaller.commandCanBeInstalled(at: command.path))
        XCTAssertEqual(try String(contentsOf: command, encoding: .utf8), "foreign")
    }

    func testInstallerCanRefreshItsOwnSymlink() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let command = directory.appendingPathComponent("briskedit")
        try FileManager.default.createSymbolicLink(
            atPath: command.path,
            withDestinationPath: CLIInstaller.launcherScriptURL.path
        )

        XCTAssertTrue(CLIInstaller.commandCanBeInstalled(at: command.path))
    }
}
