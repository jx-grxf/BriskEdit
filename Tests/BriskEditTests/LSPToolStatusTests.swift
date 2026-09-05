import XCTest
@testable import BriskEdit

final class LSPToolStatusTests: XCTestCase {
    func testDocumentOwnershipIsReferenceCountedAcrossTabs() async {
        let uri = "file:///tmp/ownership-\(UUID().uuidString).swift"
        let first = UUID()
        let second = UUID()
        LSPService.retainDocument(owner: first, language: .swift, uri: uri)
        LSPService.retainDocument(owner: second, language: .swift, uri: uri)
        XCTAssertEqual(LSPService.documentOwnerCount(uri: uri), 2)

        await LSPService.shared.releaseDocument(owner: first, language: .swift, uri: uri)
        XCTAssertEqual(LSPService.documentOwnerCount(uri: uri), 1)
        await LSPService.shared.releaseDocument(owner: second, language: .swift, uri: uri)
        XCTAssertEqual(LSPService.documentOwnerCount(uri: uri), 0)
    }

    func testRetainingOwnerAtNewURIRemovesOldOwnership() async {
        let firstURI = "file:///tmp/old-\(UUID().uuidString).txt"
        let secondURI = "file:///tmp/new-\(UUID().uuidString).swift"
        let owner = UUID()
        LSPService.retainDocument(owner: owner, language: .plainText, uri: firstURI)
        LSPService.retainDocument(owner: owner, language: .swift, uri: secondURI)
        XCTAssertEqual(LSPService.documentOwnerCount(uri: firstURI), 0)
        XCTAssertEqual(LSPService.documentOwnerCount(uri: secondURI), 1)
        await LSPService.shared.releaseDocument(owner: owner, language: .swift, uri: secondURI)
    }
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
