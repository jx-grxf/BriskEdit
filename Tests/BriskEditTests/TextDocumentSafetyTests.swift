import XCTest
@testable import BriskEdit

final class TextDocumentSafetyTests: XCTestCase {
    func testLargeFileThresholdStartsAboveFourMiB() {
        XCTAssertFalse(TextDocument.isLargeFile(byteCount: TextDocument.largeFileFeatureThresholdBytes))
        XCTAssertTrue(TextDocument.isLargeFile(byteCount: TextDocument.largeFileFeatureThresholdBytes + 1))
    }

    @MainActor
    func testLargeFileSignalTracksEdits() {
        let document = TextDocument(fileURL: nil, text: "small", encoding: .utf8)
        XCTAssertFalse(document.isLargeFile)

        document.applyEdit(text: String(repeating: "x", count: TextDocument.largeFileFeatureThresholdBytes + 1))

        XCTAssertTrue(document.isLargeFile)
    }

    @MainActor
    func testSuccessfulSavePostsGitChangeNotification() async throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("txt")
        defer { try? FileManager.default.removeItem(at: url) }

        let notification = expectation(forNotification: .gitDidChange, object: nil)
        let document = TextDocument(fileURL: url, text: "saved", encoding: .utf8)

        try await document.save()

        await fulfillment(of: [notification], timeout: 1)
        XCTAssertEqual(try String(contentsOf: url, encoding: .utf8), "saved")
    }

    func testRejectsFileAboveEditingSafetyLimit() async throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("brisk-large-\(UUID().uuidString).txt")
        FileManager.default.createFile(atPath: url.path, contents: nil)
        defer { try? FileManager.default.removeItem(at: url) }

        let handle = try FileHandle(forWritingTo: url)
        try handle.truncate(atOffset: UInt64(TextDocument.maximumEditableFileBytes + 1))
        try handle.close()

        do {
            _ = try await TextDocument.load(from: url)
            XCTFail("Expected an oversized file to be rejected")
        } catch let error as TextDocumentError {
            guard case .fileTooLarge = error else {
                return XCTFail("Unexpected TextDocumentError: \(error)")
            }
        }
    }
}
