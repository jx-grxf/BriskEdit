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

    func testTimeoutDoesNotWaitForDetachedDescendantHoldingPipes() throws {
        let started = ContinuousClock.now
        let script = "import subprocess; subprocess.Popen(['/bin/sleep','3'], start_new_session=True)"
        let result = try XCTUnwrap(BoundedProcessRunner.run(
            executableURL: URL(fileURLWithPath: "/usr/bin/python3"),
            arguments: ["-c", script],
            timeout: 0.2,
            maximumStandardOutputBytes: 1024,
            maximumStandardErrorBytes: 1024
        ))

        XCTAssertTrue(result.timedOut)
        XCTAssertLessThan(started.duration(to: .now), .seconds(1))
    }

    func testTimeoutDoesNotWaitForBlockedInputWriter() throws {
        let started = ContinuousClock.now
        let result = try XCTUnwrap(BoundedProcessRunner.run(
            executableURL: URL(fileURLWithPath: "/bin/sleep"),
            arguments: ["3"],
            input: Data(repeating: 0x61, count: 8 * 1024 * 1024),
            timeout: 0.2,
            maximumStandardOutputBytes: 1024,
            maximumStandardErrorBytes: 1024
        ))

        XCTAssertTrue(result.timedOut)
        XCTAssertLessThan(started.duration(to: .now), .seconds(1))
    }
}
