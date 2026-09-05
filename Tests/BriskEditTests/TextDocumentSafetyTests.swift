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

    @MainActor
    func testExternalConflictBlocksNormalSaveButAllowsExplicitOverwrite() async throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: url) }
        try "disk-newer".write(to: url, atomically: true, encoding: .utf8)
        let document = TextDocument(fileURL: url, text: "original", encoding: .utf8)
        document.applyEdit(text: "local-edit")
        document.externalChangePending = true

        do { try await document.save(); XCTFail("Expected conflict") }
        catch let error as TextDocumentError {
            guard case .externalChangeConflict = error else { return XCTFail("Unexpected error: \(error)") }
        }
        XCTAssertEqual(try String(contentsOf: url, encoding: .utf8), "disk-newer")
        try await document.overwriteExternalChange()
        XCTAssertEqual(try String(contentsOf: url, encoding: .utf8), "local-edit")
        XCTAssertFalse(document.externalChangePending)
    }

    @MainActor
    func testRelocationRejectsWritesUntilNewPathIsInstalled() async throws {
        let old = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let new = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: old); try? FileManager.default.removeItem(at: new) }
        try "old".write(to: old, atomically: true, encoding: .utf8)
        let document = TextDocument(fileURL: old, text: "current", encoding: .utf8)
        try await document.beginRelocation()
        do { try await document.save(); XCTFail("Expected relocation gate") }
        catch let error as TextDocumentError {
            guard case .relocationInProgress = error else { return XCTFail("Unexpected error: \(error)") }
        }
        try FileManager.default.moveItem(at: old, to: new)
        document.finishRelocation(to: new)
        try await document.save()
        XCTAssertFalse(FileManager.default.fileExists(atPath: old.path))
        XCTAssertEqual(try String(contentsOf: new, encoding: .utf8), "current")
    }

    @MainActor
    func testEmptyRecoveredDraftStaysDirtyAndAdoptsIdentityDurably() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let id = UUID()
        let draft = RecoverableDraft(id: id, filePath: "/tmp/original.swift", displayName: "original.swift",
            text: "", encodingRawValue: String.Encoding.utf8.rawValue, updatedAt: Date(),
            sessionID: UUID(), generation: 7)
        let document = TextDocument.recovered(draft)
        XCTAssertTrue(document.isDirty)
        XCTAssertEqual(document.recoveryID, id)
        let store = DraftRecoveryStore(directory: directory)
        try await document.persistRecoverySnapshotNow(minimumGeneration: 8, store: store)
        let files = try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
        XCTAssertTrue(files.contains { $0.lastPathComponent == id.uuidString + ".json" })
    }
}
