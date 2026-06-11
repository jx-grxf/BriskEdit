import XCTest
@testable import BriskEdit

final class SplitPreviewContentTests: XCTestCase {
    func testSupportsMarkdownAndNativePreviewFiles() {
        XCTAssertTrue(SplitPreviewContent.supports(URL(fileURLWithPath: "/tmp/README.md")))
        XCTAssertTrue(SplitPreviewContent.supports(URL(fileURLWithPath: "/tmp/manual.pdf")))
        XCTAssertTrue(SplitPreviewContent.supports(URL(fileURLWithPath: "/tmp/photo.png")))
        XCTAssertFalse(SplitPreviewContent.supports(URL(fileURLWithPath: "/tmp/main.swift")))
    }

    @MainActor
    func testOpeningMarkdownInSplitPreservesActiveTab() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let sourceURL = directory.appendingPathComponent("main.swift")
        let markdownURL = directory.appendingPathComponent("README.md")
        try "print(\"hi\")".write(to: sourceURL, atomically: true, encoding: .utf8)
        try "# Preview".write(to: markdownURL, atomically: true, encoding: .utf8)

        let workspace = WorkspaceModel()
        await workspace.openFile(at: sourceURL)
        let originalActiveID = try XCTUnwrap(workspace.activeTabID)

        await workspace.openInSplitScreen(markdownURL)

        XCTAssertEqual(workspace.activeTabID, originalActiveID)
        guard case .markdown(let splitTabID) = workspace.splitPreviewContent else {
            return XCTFail("Expected a Markdown split preview")
        }
        XCTAssertEqual(
            workspace.tabs.first(where: { $0.id == splitTabID })?.document.fileURL,
            markdownURL
        )
    }
}
