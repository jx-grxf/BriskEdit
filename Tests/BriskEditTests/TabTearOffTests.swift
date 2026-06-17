import AppKit
import XCTest
@testable import BriskEdit

@MainActor
final class TabTearOffTests: XCTestCase {

    // MARK: - Helpers

    private func makeWorkspace(withFiles names: [String], in directory: URL) async throws -> WorkspaceModel {
        let workspace = WorkspaceModel()
        for name in names {
            let url = directory.appendingPathComponent(name)
            try "// \(name)".write(to: url, atomically: true, encoding: .utf8)
            await workspace.openFile(at: url)
        }
        return workspace
    }

    private func tempDirectory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: directory) }
        return directory
    }

    // MARK: - detachTabForMove

    func testDetachReturnsLiveTabAndRemovesItFromSource() async throws {
        let dir = try tempDirectory()
        let workspace = try await makeWorkspace(withFiles: ["a.swift", "b.swift"], in: dir)
        let target = try XCTUnwrap(workspace.tabs.first)
        let targetID = target.id

        let detached = workspace.detachTabForMove(targetID)

        XCTAssertIdentical(detached, target, "Should hand back the very same live tab object")
        XCTAssertFalse(workspace.tabs.contains { $0.id == targetID }, "Tab must leave the source window")
        XCTAssertEqual(workspace.tabs.count, 1)
    }

    func testDetachActiveTabPicksAFallbackActiveTab() async throws {
        let dir = try tempDirectory()
        let workspace = try await makeWorkspace(withFiles: ["a.swift", "b.swift"], in: dir)
        let activeID = try XCTUnwrap(workspace.activeTabID)

        _ = workspace.detachTabForMove(activeID)

        XCTAssertNotNil(workspace.activeTabID)
        XCTAssertNotEqual(workspace.activeTabID, activeID)
        XCTAssertTrue(workspace.tabs.contains { $0.id == workspace.activeTabID })
    }

    func testDetachUnknownTabIsNoOp() async throws {
        let dir = try tempDirectory()
        let workspace = try await makeWorkspace(withFiles: ["a.swift"], in: dir)

        XCTAssertNil(workspace.detachTabForMove(UUID()))
        XCTAssertEqual(workspace.tabs.count, 1)
    }

    // MARK: - Moving a tab between windows

    func testMoveCarriesUnsavedEditsToTheTargetWindow() async throws {
        let dir = try tempDirectory()
        let source = try await makeWorkspace(withFiles: ["a.swift"], in: dir)
        let target = try await makeWorkspace(withFiles: ["x.swift"], in: dir)

        // Make an unsaved edit so we can prove the *live* document travels.
        let movingTab = try XCTUnwrap(source.tabs.first)
        movingTab.document.applyEdit(text: movingTab.document.text + "\n// EDIT")
        XCTAssertTrue(movingTab.document.isDirty)

        let detached = try XCTUnwrap(source.detachTabForMove(movingTab.id))
        target.acceptMovedTab(detached)

        XCTAssertFalse(source.tabs.contains { $0.id == movingTab.id })
        let landed = try XCTUnwrap(target.tabs.first { $0.id == movingTab.id })
        XCTAssertIdentical(landed.document, movingTab.document, "The same document object should be reused")
        XCTAssertTrue(landed.document.isDirty, "Unsaved edits must survive the move")
        XCTAssertEqual(target.activeTabID, movingTab.id, "Moved tab becomes active in the target")
        XCTAssertEqual(target.tabs.count, 2, "Appended next to the target's existing tab")
    }

    func testAcceptReplacesALonePristineUntitledTab() async throws {
        let dir = try tempDirectory()
        let source = try await makeWorkspace(withFiles: ["a.swift"], in: dir)

        // A fresh window with just an empty Untitled buffer.
        let target = WorkspaceModel()
        target.newUntitled()
        XCTAssertEqual(target.tabs.count, 1)
        XCTAssertNil(target.tabs.first?.document.fileURL)

        let moved = try XCTUnwrap(source.detachTabForMove(source.tabs.first!.id))
        target.acceptMovedTab(moved)

        XCTAssertEqual(target.tabs.count, 1, "The blank Untitled tab should be replaced, not kept")
        XCTAssertEqual(target.tabs.first?.id, moved.id)
        XCTAssertEqual(target.activeTabID, moved.id)
    }

    func testAcceptAppendsWhenTargetHasRealContent() async throws {
        let dir = try tempDirectory()
        let source = try await makeWorkspace(withFiles: ["a.swift"], in: dir)
        let target = try await makeWorkspace(withFiles: ["x.swift", "y.swift"], in: dir)
        let countBefore = target.tabs.count

        let moved = try XCTUnwrap(source.detachTabForMove(source.tabs.first!.id))
        target.acceptMovedTab(moved)

        XCTAssertEqual(target.tabs.count, countBefore + 1)
    }

    // MARK: - moveTab (in-strip reorder)

    private func tabNames(_ workspace: WorkspaceModel) -> [String] {
        workspace.tabs.map { $0.document.fileURL?.lastPathComponent ?? $0.displayTitle }
    }

    private func tabID(_ workspace: WorkspaceModel, _ name: String) throws -> EditorTab.ID {
        try XCTUnwrap(workspace.tabs.first { $0.document.fileURL?.lastPathComponent == name }).id
    }

    func testMoveTabRightwardsLandsAfterTarget() async throws {
        let dir = try tempDirectory()
        let workspace = try await makeWorkspace(withFiles: ["a.swift", "b.swift", "c.swift", "d.swift"], in: dir)

        workspace.moveTab(try tabID(workspace, "a.swift"), toPositionOf: try tabID(workspace, "c.swift"))

        XCTAssertEqual(tabNames(workspace), ["b.swift", "c.swift", "a.swift", "d.swift"])
    }

    func testMoveTabLeftwardsLandsBeforeTarget() async throws {
        let dir = try tempDirectory()
        let workspace = try await makeWorkspace(withFiles: ["a.swift", "b.swift", "c.swift", "d.swift"], in: dir)

        workspace.moveTab(try tabID(workspace, "d.swift"), toPositionOf: try tabID(workspace, "b.swift"))

        XCTAssertEqual(tabNames(workspace), ["a.swift", "d.swift", "b.swift", "c.swift"])
    }

    func testMoveTabOntoItselfIsNoOp() async throws {
        let dir = try tempDirectory()
        let workspace = try await makeWorkspace(withFiles: ["a.swift", "b.swift", "c.swift"], in: dir)
        let id = try tabID(workspace, "b.swift")

        workspace.moveTab(id, toPositionOf: id)

        XCTAssertEqual(tabNames(workspace), ["a.swift", "b.swift", "c.swift"])
    }

    func testMoveUnknownTabIsNoOp() async throws {
        let dir = try tempDirectory()
        let workspace = try await makeWorkspace(withFiles: ["a.swift", "b.swift"], in: dir)

        workspace.moveTab(UUID(), toPositionOf: try tabID(workspace, "a.swift"))

        XCTAssertEqual(tabNames(workspace), ["a.swift", "b.swift"])
    }

    // MARK: - moveActiveTab (keyboard reorder)

    func testMoveActiveTabRightThenLeft() async throws {
        let dir = try tempDirectory()
        let workspace = try await makeWorkspace(withFiles: ["a.swift", "b.swift", "c.swift"], in: dir)
        workspace.selectTab(try tabID(workspace, "a.swift"))

        workspace.moveActiveTab(by: 1)
        XCTAssertEqual(tabNames(workspace), ["b.swift", "a.swift", "c.swift"])

        workspace.moveActiveTab(by: -1)
        XCTAssertEqual(tabNames(workspace), ["a.swift", "b.swift", "c.swift"])
    }

    func testMoveActiveTabPastTheEndIsNoOp() async throws {
        let dir = try tempDirectory()
        let workspace = try await makeWorkspace(withFiles: ["a.swift", "b.swift"], in: dir)
        workspace.selectTab(try tabID(workspace, "b.swift"))

        workspace.moveActiveTab(by: 1) // already last

        XCTAssertEqual(tabNames(workspace), ["a.swift", "b.swift"])
        XCTAssertEqual(workspace.activeTabID, try tabID(workspace, "b.swift"))
    }

    // MARK: - insertMovedTab (cross-window drop at a position)

    func testInsertMovedTabLandsAtTargetSlot() async throws {
        let dir = try tempDirectory()
        let source = try await makeWorkspace(withFiles: ["dragged.swift"], in: dir)
        let target = try await makeWorkspace(withFiles: ["x.swift", "y.swift", "z.swift"], in: dir)

        let moved = try XCTUnwrap(source.detachTabForMove(source.tabs.first!.id))
        target.insertMovedTab(moved, before: try tabID(target, "y.swift"))

        XCTAssertEqual(tabNames(target), ["x.swift", "dragged.swift", "y.swift", "z.swift"])
        XCTAssertEqual(target.activeTabID, moved.id)
    }

    func testInsertMovedTabReplacesLonePristineUntitled() async throws {
        let dir = try tempDirectory()
        let source = try await makeWorkspace(withFiles: ["dragged.swift"], in: dir)
        let target = WorkspaceModel()
        target.newUntitled()
        let untitledID = try XCTUnwrap(target.tabs.first?.id)

        let moved = try XCTUnwrap(source.detachTabForMove(source.tabs.first!.id))
        target.insertMovedTab(moved, before: untitledID)

        XCTAssertEqual(target.tabs.count, 1, "The blank Untitled tab is replaced, not pushed aside")
        XCTAssertEqual(target.tabs.first?.id, moved.id)
    }

    // MARK: - adoptTornOffTab (new window)

    func testAdoptInheritsFolderAndMakesTabActive() async throws {
        let dir = try tempDirectory()
        let source = try await makeWorkspace(withFiles: ["a.swift"], in: dir)
        source.setWorkspaceRoot(dir)

        let moved = try XCTUnwrap(source.detachTabForMove(source.tabs.first!.id))

        let fresh = WorkspaceModel()
        fresh.adoptTornOffTab(moved, rootURL: dir)

        XCTAssertEqual(fresh.rootURL, dir, "New window inherits the source folder")
        XCTAssertEqual(fresh.tabs.count, 1)
        XCTAssertEqual(fresh.tabs.first?.id, moved.id)
        XCTAssertEqual(fresh.activeTabID, moved.id)
    }

    // MARK: - Drop-point geometry

    func testTearOffFramePlacesTopLeftAtDropPointAndFillsFreeArea() {
        // A 1440×900 visible area at origin; drop a third of the way in/down.
        let visible = CGRect(x: 0, y: 0, width: 1440, height: 900)
        let drop = CGPoint(x: 400, y: 700) // 700 from bottom → top-left near the top

        let frame = TabTearOffGeometry.frame(dropPoint: drop, visibleFrame: visible)

        XCTAssertEqual(frame.minX, 400, accuracy: 0.5, "Left edge at the drop point")
        XCTAssertEqual(frame.maxY, 700, accuracy: 0.5, "Top edge at the drop point")
        XCTAssertEqual(frame.maxX, visible.maxX, accuracy: 0.5, "Fills to the right edge")
        XCTAssertEqual(frame.minY, visible.minY, accuracy: 0.5, "Fills down to the bottom edge")
    }

    func testTearOffFrameClampsToMinimumSizeNearACorner() {
        let visible = CGRect(x: 0, y: 0, width: 1440, height: 900)
        // Drop in the bottom-right corner: almost no free space down-and-right.
        let drop = CGPoint(x: 1430, y: 10)

        let frame = TabTearOffGeometry.frame(dropPoint: drop, visibleFrame: visible)

        XCTAssertEqual(frame.width, TabTearOffGeometry.minSize.width, accuracy: 0.5)
        XCTAssertEqual(frame.height, TabTearOffGeometry.minSize.height, accuracy: 0.5)
        // Shifted back so the whole window stays on screen.
        XCTAssertGreaterThanOrEqual(frame.minX, visible.minX)
        XCTAssertGreaterThanOrEqual(frame.minY, visible.minY)
        XCTAssertLessThanOrEqual(frame.maxX, visible.maxX + 0.5)
        XCTAssertLessThanOrEqual(frame.maxY, visible.maxY + 0.5)
    }

    func testTearOffFrameRespectsNonZeroScreenOrigin() {
        // A secondary display offset from the main one (menu-bar inset on top).
        let visible = CGRect(x: 1440, y: 0, width: 1920, height: 1055)
        let drop = CGPoint(x: 2000, y: 900)

        let frame = TabTearOffGeometry.frame(dropPoint: drop, visibleFrame: visible)

        XCTAssertEqual(frame.minX, 2000, accuracy: 0.5)
        XCTAssertEqual(frame.maxY, 900, accuracy: 0.5)
        XCTAssertEqual(frame.maxX, visible.maxX, accuracy: 0.5)
        XCTAssertEqual(frame.minY, visible.minY, accuracy: 0.5)
    }
}
