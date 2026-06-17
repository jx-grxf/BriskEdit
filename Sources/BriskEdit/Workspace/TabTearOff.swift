import AppKit
import SwiftUI
import UniformTypeIdentifiers

/// Drives "tearing off" a tab and moving it between windows: drag a tab out and
/// drop it on another BriskEdit window to move it there, or onto empty desktop
/// to reopen it in a fresh window placed where you dropped it.
///
/// Jobs:
/// 1. **Hand-off.** `openWindow(value:)` only carries `Codable` values, so a live
///    `EditorTab` (a reference type with unsaved edits and a language-server
///    registration) can't ride along. Instead the source window stashes the tab
///    here keyed by the new window's UUID; the new window claims it on appear.
/// 2. **Window lookup.** Each live window registers its `WorkspaceModel`, so a
///    drop can be routed into whatever window sits under the cursor.
///
/// The drag itself is SwiftUI's native `.draggable` (`makeTabTransfer`) — the
/// exact drag path the file tree uses (`.draggable(node.url)`), which is the only
/// mechanism that actually fires inside the tab strip's `ScrollView` (legacy
/// `.onDrag`, hand-rolled `DragGesture`s and `NSDraggingSession`s all stayed
/// inert there). `.draggable` gives no end callback, and SwiftUI doesn't release
/// the `Transferable` payload at a usable moment, so we detect the session end
/// ourselves: while a drag is in flight we poll the physical mouse button and
/// route the instant it releases, by hit-testing the cursor's release point.
@MainActor
final class TabTearOffCoordinator {
    static let shared = TabTearOffCoordinator()

    struct Payload {
        let tab: EditorTab
        let rootURL: URL?
    }

    private final class Weak<T: AnyObject> {
        weak var value: T?
        init(_ value: T?) { self.value = value }
    }

    private var pending: [UUID: Payload] = [:]
    /// Where a torn-off window should open, in screen coordinates. Read by
    /// `WindowConfigurator` so the new window lands at the drop point instead of
    /// the default full-screen frame.
    private var pendingFrames: [UUID: CGRect] = [:]
    private var registrations: [ObjectIdentifier: (window: Weak<NSWindow>, workspace: Weak<WorkspaceModel>)] = [:]

    /// The tab currently being dragged (its id + the window it came from).
    private var inFlightTabID: UUID?
    private var inFlightSource: Weak<WorkspaceModel>?
    /// Polls the mouse button while a drag is live; fires `finishDrag` on release.
    private var endPollTimer: Timer?

    private init() {}

    // MARK: - In-flight drag (started by `.draggable`)

    func beginDrag(tabID: UUID, source: WorkspaceModel) {
        inFlightTabID = tabID
        inFlightSource = Weak(source)
        startEndPolling()
    }

    /// `.draggable` has no end callback, so we watch the physical mouse button:
    /// the drag begins with it held down, and the session ends the moment it's
    /// released. The timer is registered in both the common and event-tracking
    /// run-loop modes so it ticks whether or not the drag loop has taken over —
    /// worst case it fires on the first tick after the drag loop returns, which is
    /// still right after release. The cursor hasn't moved meaningfully in the poll
    /// interval, so `NSEvent.mouseLocation` still reads the release point.
    private func startEndPolling() {
        endPollTimer?.invalidate()
        let timer = Timer(timeInterval: 0.02, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                // Still dragging while the left button is down.
                guard NSEvent.pressedMouseButtons & 0x1 == 0 else { return }
                self.endPollTimer?.invalidate()
                self.endPollTimer = nil
                self.finishDrag()
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        RunLoop.main.add(timer, forMode: .eventTracking)
        endPollTimer = timer
    }

    /// Routes the dragged tab to wherever it was released: we hit-test our windows
    /// at the cursor's release point — over a BriskEdit window → move the tab in
    /// (back into the source window is a no-op); over empty desktop → tear off into
    /// a new window at that point.
    func finishDrag() {
        endPollTimer?.invalidate()
        endPollTimer = nil
        guard let tabID = inFlightTabID, let source = inFlightSource?.value else {
            inFlightTabID = nil
            inFlightSource = nil
            return
        }
        inFlightTabID = nil
        inFlightSource = nil

        let dropPoint = NSEvent.mouseLocation
        if let target = dropTarget(at: dropPoint) {
            guard target.workspace !== source else { return }
            guard let tab = source.detachTabForMove(tabID) else { return }
            target.workspace.acceptMovedTab(tab)
            target.window.makeKeyAndOrderFront(nil)
            return
        }

        guard let tab = source.detachTabForMove(tabID) else { return }
        let newWindowID = UUID()
        stash(tab: tab, rootURL: source.rootURL, frame: tearOffFrame(at: dropPoint), for: newWindowID)
        NewWindowCoordinator.shared.openValue?(.secondary(newWindowID))
    }

    /// Moves the in-flight tab into `target` at the slot held by `targetID` — used
    /// when a tab dragged from another window is dropped directly onto a chip, so
    /// the cross-window move lands at the drop position instead of appending.
    /// Clears the in-flight state so the trailing `finishDrag` poll no-ops.
    /// Returns false (leaving the drag alone) for a same-window drop or when the
    /// tab can't be detached.
    @discardableResult
    func moveInFlightTab(toPositionOf targetID: UUID, into target: WorkspaceModel) -> Bool {
        guard let tabID = inFlightTabID,
              let source = inFlightSource?.value,
              source !== target,
              let tab = source.detachTabForMove(tabID) else { return false }
        target.insertMovedTab(tab, before: targetID)
        inFlightTabID = nil
        inFlightSource = nil
        endPollTimer?.invalidate()
        endPollTimer = nil
        return true
    }

    /// Frame for a window torn off at `dropPoint` (top-left there, filling the free
    /// desktop area), resolving the screen under the cursor.
    private func tearOffFrame(at dropPoint: CGPoint) -> CGRect {
        let screen = NSScreen.screens.first(where: { $0.frame.contains(dropPoint) })
            ?? NSScreen.main ?? NSScreen.screens.first
        let visible = screen?.visibleFrame ?? CGRect(origin: dropPoint, size: TabTearOffGeometry.minSize)
        return TabTearOffGeometry.frame(dropPoint: dropPoint, visibleFrame: visible)
    }

    // MARK: - Window hand-off

    /// Records a tab (and the frame the new window should open at) so the window
    /// about to open for `id` can adopt it.
    func stash(tab: EditorTab, rootURL: URL?, frame: CGRect?, for id: UUID) {
        pending[id] = Payload(tab: tab, rootURL: rootURL)
        if let frame { pendingFrames[id] = frame }
    }

    /// Claims (and clears) the tab stashed for a window, if any. Returns nil for
    /// plain "New Window" commands, which carry no payload.
    func takePayload(for id: UUID) -> Payload? {
        pending.removeValue(forKey: id)
    }

    /// The frame a torn-off window should open at, if one was stashed. Read (not
    /// cleared) so it stays stable across SwiftUI's body re-renders; cleared via
    /// `clearFrame(for:)` once the window has settled.
    func frame(for id: UUID) -> CGRect? {
        pendingFrames[id]
    }

    func clearFrame(for id: UUID) {
        pendingFrames.removeValue(forKey: id)
    }

    // MARK: - Window ↔ workspace registry

    /// Associates a live window with its workspace so drops can be routed into it.
    /// Sweeps entries whose window or workspace has been deallocated first, so the
    /// registry doesn't grow unbounded across a long session of opening/closing
    /// windows.
    func register(window: NSWindow, workspace: WorkspaceModel) {
        registrations = registrations.filter { $0.value.window.value != nil && $0.value.workspace.value != nil }
        registrations[ObjectIdentifier(window)] = (Weak(window), Weak(workspace))
    }

    /// The frontmost registered window whose frame contains `point`, with its
    /// workspace — i.e. the window a tab dropped at `point` should move into.
    func dropTarget(at point: CGPoint) -> (window: NSWindow, workspace: WorkspaceModel)? {
        for window in NSApp.orderedWindows
        where window.isVisible && window.frame.contains(point) {
            if let entry = registrations[ObjectIdentifier(window)],
               let workspace = entry.workspace.value {
                return (window, workspace)
            }
        }
        return nil
    }
}

/// Geometry for a torn-off window: where it should open relative to the drop
/// point. Pure (no `NSScreen`) so it can be unit-tested.
enum TabTearOffGeometry {
    static let minSize = CGSize(width: 900, height: 560)

    /// A frame whose top-left sits at `dropPoint` and that fills the free desktop
    /// area down-and-right to the screen edges, clamped to `minSize` and kept
    /// fully inside `visibleFrame`. Coordinates are Cocoa screen coordinates
    /// (origin bottom-left).
    static func frame(dropPoint: CGPoint, visibleFrame: CGRect) -> CGRect {
        let width = max(minSize.width, visibleFrame.maxX - dropPoint.x)
        let height = max(minSize.height, dropPoint.y - visibleFrame.minY)
        var originX = dropPoint.x
        var originY = dropPoint.y - height
        // Keep the whole window within the visible frame (lower bound wins if the
        // window is wider/taller than the screen).
        originX = min(max(originX, visibleFrame.minX), visibleFrame.maxX - width)
        originY = min(max(originY, visibleFrame.minY), visibleFrame.maxY - height)
        return CGRect(x: originX, y: originY, width: width, height: height)
    }
}

extension UTType {
    /// Own-app drag type for a torn-off editor tab. No other app understands it,
    /// so dropping a tab outside BriskEdit is inert (no stray text/file clipping
    /// on the desktop) — the same intent the old `.ownProcess` item provider had.
    static let briskEditTab = UTType(exportedAs: "com.johannesgrof.briskedit.tab", conformingTo: .data)
}

/// The `.draggable` payload for a torn-off tab. It only needs to carry the tab's
/// id and be a type no other app understands (so a drop outside BriskEdit is
/// inert); the actual routing reads the in-flight drag from the coordinator, not
/// this payload, so the data representation just round-trips the id.
struct TabTransfer: Transferable {
    let tabID: UUID

    static var transferRepresentation: some TransferRepresentation {
        DataRepresentation(contentType: .briskEditTab) { transfer in
            Data(transfer.tabID.uuidString.utf8)
        } importing: { data in
            TabTransfer(tabID: UUID(uuidString: String(decoding: data, as: UTF8.self)) ?? UUID())
        }
    }
}

/// Starts a tab drag: registers the in-flight tab with the coordinator and returns
/// the `.draggable` payload. Mirrors the file tree's native `.draggable(node.url)`
/// — the only drag mechanism that fires inside the tab strip's `ScrollView`.
///
/// `.draggable` evaluates its payload autoclosure when the drag actually begins,
/// so the left button is down by then; we guard on that so a stray eager
/// evaluation (no button held) can't arm a phantom drag that the end-poll would
/// immediately "finish" and teleport a tab.
@MainActor
func makeTabTransfer(tabID: UUID, source: WorkspaceModel) -> TabTransfer {
    if NSEvent.pressedMouseButtons & 0x1 != 0 {
        TabTearOffCoordinator.shared.beginDrag(tabID: tabID, source: source)
    }
    return TabTransfer(tabID: tabID)
}

/// Reports the `NSWindow` hosting a SwiftUI view, so the tab strip can tell
/// whether a drag was released inside its own window or out on the desktop.
struct WindowAccessor: NSViewRepresentable {
    let onResolve: (NSWindow?) -> Void

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async { onResolve(view.window) }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        DispatchQueue.main.async { onResolve(nsView.window) }
    }
}
