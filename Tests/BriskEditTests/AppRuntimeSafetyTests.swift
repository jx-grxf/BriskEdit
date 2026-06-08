import Foundation
import XCTest
@testable import BriskEdit

final class AppRuntimeSafetyTests: XCTestCase {
    func testClosedPipeWriteThrowsInsteadOfTerminatingProcess() throws {
        AppRuntimeSafety.install()

        let pipe = Pipe()
        try pipe.fileHandleForReading.close()

        XCTAssertThrowsError(
            try pipe.fileHandleForWriting.write(contentsOf: Data([0x41]))
        )
    }
}
