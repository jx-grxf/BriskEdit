import XCTest
@testable import BriskEdit

final class LSPToolStatusTests: XCTestCase {
    func testConfigDisplayNamesMatchStatusBarLabels() {
        XCTAssertEqual(LSPService.config(for: .c)?.displayName, "clangd")
        XCTAssertEqual(LSPService.config(for: .swift)?.displayName, "sourcekit-lsp")
        XCTAssertEqual(LSPService.config(for: .java)?.displayName, "jdtls")
        XCTAssertEqual(LSPService.config(for: .typescript)?.displayName, "typescript-language-server")
    }

    func testPlainTextHasNoLanguageServer() async {
        let status = await LSPService.toolStatus(for: .plainText)

        XCTAssertEqual(status.state, .unsupported)
        XCTAssertEqual(status.serverName, "Off")
    }
}
