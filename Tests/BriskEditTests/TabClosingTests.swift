import AppKit
import XCTest
@testable import BriskEdit

@MainActor
final class TabClosingTests: XCTestCase {
    func testLateSelectionCannotReactivateClosedTab() throws {
        let workspace = makeWorkspace()
        let closedID = try XCTUnwrap(workspace.activeTabID)
        workspace.requestCloseTab(closedID)
        let fallback = workspace.activeTabID

        // A delayed gesture from a removed view must not invalidate selection.
        workspace.selectTab(closedID)

        XCTAssertEqual(workspace.tabs.count, 2)
        XCTAssertEqual(workspace.activeTabID, fallback)
        XCTAssertNotNil(workspace.activeTab)
    }

    func testRepeatedCloseAndLateCallbacksReachEmptyWorkspace() throws {
        let workspace = makeWorkspace()
        let original = workspace.tabs.map(\.id)
        for (index, id) in original.reversed().enumerated() {
            workspace.requestCloseTab(id)
            workspace.selectTab(id)
            workspace.requestCloseTab(id)
            // SwiftUI can rebuild transfer values while the click is still held.
            for remaining in workspace.tabs {
                _ = TabTransfer(tabID: remaining.id)
            }
            XCTAssertEqual(workspace.tabs.count, original.count - index - 1)
            XCTAssertFalse(TabTearOffCoordinator.shared.hasActiveDrag)
        }
        XCTAssertTrue(workspace.tabs.isEmpty)
        XCTAssertNil(workspace.activeTabID)
    }

    func testConstructingTransfersDoesNotArmDragOrMoveTabs() {
        let workspace = makeWorkspace()
        let ids = workspace.tabs.map(\.id)
        for _ in 0..<50 {
            for id in ids { _ = TabTransfer(tabID: id) }
        }
        TabTearOffCoordinator.shared.finishDrag()
        XCTAssertEqual(workspace.tabs.map(\.id), ids)
        XCTAssertFalse(TabTearOffCoordinator.shared.hasActiveDrag)
    }

    func testClosingDraggedTabCancelsItsPendingTearOff() throws {
        let workspace = makeWorkspace()
        let id = try XCTUnwrap(workspace.activeTabID)
        let coordinator = TabTearOffCoordinator.shared
        defer { coordinator.cancelDrag() }
        coordinator.beginDrag(tabID: id, source: workspace)
        XCTAssertTrue(coordinator.hasActiveDrag)

        workspace.requestCloseTab(id)
        coordinator.finishDrag()

        XCTAssertFalse(coordinator.hasActiveDrag)
        XCTAssertEqual(workspace.tabs.count, 2)
        XCTAssertFalse(workspace.tabs.contains { $0.id == id })
    }

    func testCancelledDragKeepsDocumentInSource() throws {
        let workspace = makeWorkspace()
        let id = try XCTUnwrap(workspace.activeTabID)
        let coordinator = TabTearOffCoordinator()
        coordinator.beginDrag(tabID: id, source: workspace)
        coordinator.cancelDrag()
        coordinator.finishDrag()
        XCTAssertEqual(workspace.tabs.count, 3)
        XCTAssertEqual(workspace.activeTabID, id)
    }

    func testGenuineCrossWindowDragStillMovesLiveTab() throws {
        let source = makeWorkspace()
        let target = makeWorkspace()
        let tab = try XCTUnwrap(source.activeTab)
        let targetID = try XCTUnwrap(target.activeTabID)
        let coordinator = TabTearOffCoordinator()
        defer { coordinator.cancelDrag() }
        coordinator.beginDrag(tabID: tab.id, source: source)

        XCTAssertTrue(coordinator.moveInFlightTab(toPositionOf: targetID, into: target))
        XCTAssertEqual(source.tabs.count, 2)
        XCTAssertEqual(target.tabs.count, 4)
        XCTAssertTrue(target.activeTab === tab)
        XCTAssertFalse(coordinator.hasActiveDrag)
    }

    private func makeWorkspace() -> WorkspaceModel {
        let workspace = WorkspaceModel()
        for _ in 0..<3 { workspace.newUntitled() }
        return workspace
    }
}
