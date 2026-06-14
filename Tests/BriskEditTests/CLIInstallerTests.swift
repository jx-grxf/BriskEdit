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
        // `brisk .` and relative paths work from any working directory.
        XCTAssertTrue(script.contains(#"cd "$(dirname "$arg")""#))
        XCTAssertTrue(script.contains("pwd"))
    }

    func testLauncherScriptHandlesNoArguments() {
        XCTAssertTrue(CLIInstaller.launcherScript.contains(#"if [ "$#" -eq 0 ]"#))
    }

    func testLauncherScriptLivesUnderApplicationSupport() {
        XCTAssertEqual(CLIInstaller.launcherScriptURL.lastPathComponent, "brisk")
        XCTAssertTrue(CLIInstaller.launcherScriptURL.path.contains("Application Support/BriskEdit"))
    }
}
