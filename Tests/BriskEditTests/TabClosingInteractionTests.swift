import AppKit
import SwiftUI
import XCTest
@testable import BriskEdit

private final class NonActivatingCloseTestPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

@MainActor
final class TabClosingInteractionTests: XCTestCase {
    func testClickingCloseRepeatedlyRemovesExactlyOneTab() async throws {
        let workspace = WorkspaceModel()
        workspace.showTerminal = false
        for _ in 0..<3 { workspace.newUntitled() }
        let ids = workspace.tabs.map(\.id)
        let previousOpenWindow = NewWindowCoordinator.shared.openValue
        var unexpectedWindows = 0
        NewWindowCoordinator.shared.openValue = { _ in unexpectedWindows += 1 }
        defer { NewWindowCoordinator.shared.openValue = previousOpenWindow }
        let prefs = Preferences()
        let view = NSHostingView(rootView: CloseTestTabs(workspace: workspace).environment(prefs))
        let panel = NonActivatingCloseTestPanel(contentRect: NSRect(x: 100, y: 100, width: 720, height: 32),
            styleMask: [.titled, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.isReleasedWhenClosed = false
        panel.isFloatingPanel = false
        panel.level = .normal
        panel.title = "Background close-button regression"
        panel.contentView = view
        panel.orderBack(nil)
        defer { panel.close(); TabTearOffCoordinator.shared.cancelDrag() }
        try await Task.sleep(for: .milliseconds(400))

        for (offset, id) in [ids[2], ids[0], ids[1]].enumerated() {
            let index = try XCTUnwrap(workspace.tabs.firstIndex { $0.id == id })
            let point = NSPoint(x: CGFloat(index + 1) * 240 - 16, y: 16)
            let timestamp = ProcessInfo.processInfo.systemUptime
            let down = try XCTUnwrap(NSEvent.mouseEvent(with: .leftMouseDown, location: point, modifierFlags: [],
                timestamp: timestamp, windowNumber: panel.windowNumber, context: nil, eventNumber: 1, clickCount: 1, pressure: 1))
            let up = try XCTUnwrap(NSEvent.mouseEvent(with: .leftMouseUp, location: point, modifierFlags: [],
                timestamp: timestamp + 0.02, windowNumber: panel.windowNumber, context: nil, eventNumber: 2, clickCount: 1, pressure: 0))
            NSApp.postEvent(up, atStart: true)
            panel.sendEvent(down)
            try await Task.sleep(for: .milliseconds(350))
            XCTAssertEqual(workspace.tabs.count, 2 - offset)
            XCTAssertFalse(workspace.tabs.contains { $0.id == id })
            XCTAssertFalse(TabTearOffCoordinator.shared.hasActiveDrag)
            if !workspace.tabs.isEmpty { XCTAssertNotNil(workspace.activeTab) }
        }
        XCTAssertNil(workspace.activeTabID)
        XCTAssertEqual(unexpectedWindows, 0)
    }

}

private struct CloseTestTabs: View {
    @Bindable var workspace: WorkspaceModel

    var body: some View {
        HStack(spacing: 0) {
            ForEach(workspace.tabs) { tab in
                TabChip(tab: tab, isActive: tab.id == workspace.activeTabID,
                    onSelect: { workspace.selectTab(tab.id) },
                    onClose: { workspace.requestCloseTab(tab.id) },
                    onCloseOthers: {}, onCloseRight: {}, onCloseAll: {}, onOpenSplitPreview: {},
                    source: workspace, onReorder: { _ in })
                    .frame(width: 240)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }
}
