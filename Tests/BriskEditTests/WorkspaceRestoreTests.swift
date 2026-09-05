import XCTest
@testable import BriskEdit

@MainActor
final class WorkspaceRestoreTests: XCTestCase {
    func testUserInteractionInvalidatesInFlightRestore() async throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: url) }
        try "saved".write(to: url, atomically: true, encoding: .utf8)
        let defaults = UserDefaults.standard
        let oldFiles = defaults.stringArray(forKey: WorkspaceModel.Keys.openSessionFiles)
        let oldActive = defaults.string(forKey: WorkspaceModel.Keys.activeSessionFile)
        defer {
            defaults.set(oldFiles, forKey: WorkspaceModel.Keys.openSessionFiles)
            defaults.set(oldActive, forKey: WorkspaceModel.Keys.activeSessionFile)
        }
        defaults.set([url.path], forKey: WorkspaceModel.Keys.openSessionFiles)
        defaults.set(url.path, forKey: WorkspaceModel.Keys.activeSessionFile)
        let workspace = WorkspaceModel()
        workspace.sessionDocumentLoader = { url in
            try await Task.sleep(for: .milliseconds(100))
            return try await TextDocument.load(from: url)
        }
        let restore = Task { await workspace.restoreSession() }
        try await Task.sleep(for: .milliseconds(10))
        workspace.newUntitled()
        await restore.value
        XCTAssertEqual(workspace.tabs.count, 1)
        XCTAssertNil(workspace.tabs.first?.document.fileURL)
    }
}
