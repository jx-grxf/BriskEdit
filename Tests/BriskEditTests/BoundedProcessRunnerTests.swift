import XCTest
@testable import BriskEdit

final class BoundedProcessRunnerTests: XCTestCase {
    func testCapsCapturedOutput() throws {
        let result = try XCTUnwrap(BoundedProcessRunner.run(
            executableURL: URL(fileURLWithPath: "/bin/zsh"),
            arguments: ["-lc", "yes x | head -c 65536"],
            timeout: 2,
            maximumStandardOutputBytes: 1024,
            maximumStandardErrorBytes: 1024
        ))

        XCTAssertEqual(result.stdout.count, 1024)
        XCTAssertTrue(result.outputLimitExceeded)
        XCTAssertFalse(result.timedOut)
    }

    func testTerminatesTimedOutProcess() throws {
        let result = try XCTUnwrap(BoundedProcessRunner.run(
            executableURL: URL(fileURLWithPath: "/bin/zsh"),
            arguments: ["-lc", "exec sleep 5"],
            timeout: 0.1,
            maximumStandardOutputBytes: 1024,
            maximumStandardErrorBytes: 1024
        ))

        XCTAssertTrue(result.timedOut)
    }
}
