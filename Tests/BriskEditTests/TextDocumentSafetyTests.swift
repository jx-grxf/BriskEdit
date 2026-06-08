import XCTest
@testable import BriskEdit

final class TextDocumentSafetyTests: XCTestCase {
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
