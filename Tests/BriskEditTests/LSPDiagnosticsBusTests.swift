import XCTest
@testable import BriskEdit

@MainActor
final class LSPDiagnosticsBusTests: XCTestCase {
    func testMultipleEditorsReceiveDiagnosticsForSameURI() {
        let bus = LSPDiagnosticsBus()
        var firstCount = 0
        var secondCount = 0
        let first = bus.subscribe(uri: "file:///same.py") { _ in firstCount += 1 }
        _ = bus.subscribe(uri: "file:///same.py") { _ in secondCount += 1 }

        bus.deliver(uri: "file:///same.py", diagnostics: [])
        XCTAssertEqual(firstCount, 1)
        XCTAssertEqual(secondCount, 1)

        bus.unsubscribe(uri: "file:///same.py", token: first)
        bus.deliver(uri: "file:///same.py", diagnostics: [])
        XCTAssertEqual(firstCount, 1)
        XCTAssertEqual(secondCount, 2)
    }
}
