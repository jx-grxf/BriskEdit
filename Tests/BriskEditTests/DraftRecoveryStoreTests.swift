import XCTest
@testable import BriskEdit

final class DraftRecoveryStoreTests: XCTestCase {
    func testCurrentSessionDraftIsNotOfferedAsRecovery() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = DraftRecoveryStore(directory: directory)
        try await store.save(id: UUID(), generation: 1, fileURL: nil, displayName: "Untitled", text: "work")
        let drafts = try await store.recoverableDrafts()
        XCTAssertTrue(drafts.isEmpty)
    }

    func testOversizedDraftIsRejected() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = DraftRecoveryStore(directory: directory)
        do {
            try await store.save(id: UUID(), generation: 1, fileURL: nil, displayName: "Large", text: String(repeating: "x", count: DraftRecoveryStore.maximumDraftBytes + 1))
            XCTFail("Expected size cap")
        } catch let error as DraftRecoveryError {
            guard case .draftTooLarge = error else { return XCTFail("Unexpected error: \(error)") }
        }
    }

    func testStaleSaveCannotResurrectRemovedDraft() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = DraftRecoveryStore(directory: directory)
        let id = UUID()
        try await store.remove(id: id, generation: 2)
        try await store.save(id: id, generation: 1, fileURL: nil, displayName: "Old", text: "stale")
        let files = (try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)) ?? []
        XCTAssertFalse(files.contains { $0.lastPathComponent == id.uuidString + ".json" })
    }

    func testCurrentSessionDraftQuotaIsEnforced() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = DraftRecoveryStore(directory: directory)
        for index in 0..<DraftRecoveryStore.maximumDraftCount {
            try await store.save(id: UUID(), generation: 1, fileURL: nil, displayName: "D\(index)", text: "x")
        }
        do {
            try await store.save(id: UUID(), generation: 1, fileURL: nil, displayName: "Overflow", text: "x")
            XCTFail("Expected quota error")
        } catch let error as DraftRecoveryError {
            guard case .storageLimitReached = error else { return XCTFail("Unexpected error: \(error)") }
        }
    }

    func testControlHeavyDraftRoundTripsWithoutUnreadableWarning() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = DraftRecoveryStore(directory: directory)
        let text = String(repeating: "\n\t\"\\", count: DraftRecoveryStore.maximumDraftBytes / 4)
        try await store.save(id: UUID(), generation: 1, fileURL: nil, displayName: "Escapes", text: text)
        _ = try await store.recoverableDrafts()
        let warnings = await store.takeWarnings()
        XCTAssertTrue(warnings.isEmpty)
    }
}
