import AppKit
import SwiftTerm
import SwiftUI

struct TerminalPanel: View {
    @Bindable var workspace: WorkspaceModel
    @Environment(Preferences.self) private var preferences

    private var activeTerminal: TerminalController? { workspace.activeTerminal }

    var body: some View {
        VStack(spacing: 0) {
            toolbar
            Divider()
            terminalSurface
        }
        .task {
            if workspace.terminals.isEmpty {
                workspace.addTerminal()
            }
        }
    }

    private var toolbar: some View {
        HStack(spacing: 8) {
            Label(activeTerminal?.title ?? "Terminal", systemImage: "terminal")
                .font(.caption.weight(.semibold))
                .lineLimit(1)
            if let path = activeTerminal?.currentDirectory.path {
                Text(path)
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }

            sessionList

            Spacer(minLength: 8)

            Circle()
                .fill((activeTerminal?.isRunning ?? false) ? Color.green : Color.secondary)
                .frame(width: 7, height: 7)
            Button("New Shell", systemImage: "plus") {
                workspace.addTerminal()
            }
            Button("Clear", systemImage: "trash") {
                activeTerminal?.clear()
            }
            Button("Hide", systemImage: "rectangle.bottomthird.inset.filled") {
                workspace.hideTerminal()
            }
        }
        .buttonStyle(.borderless)
        .padding(.horizontal, 10)
        .frame(height: 34)
        .background(.bar)
    }

    /// Horizontal strip of open sessions; click to switch, trash to close.
    private var sessionList: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(workspace.terminals) { terminal in
                    TerminalSessionChip(
                        name: terminal.name,
                        isActive: terminal.id == activeTerminal?.id,
                        onSelect: { workspace.selectTerminal(terminal.id) },
                        onClose: { workspace.closeTerminal(terminal.id) }
                    )
                }
            }
            .padding(.vertical, 3)
        }
        .frame(maxWidth: 360)
    }

    @ViewBuilder
    private var terminalSurface: some View {
        if workspace.terminals.isEmpty {
            ContentUnavailableView {
                Label("No Terminal", systemImage: "terminal")
            } description: {
                Text("All shells are closed.")
            } actions: {
                Button("New Shell") { workspace.addTerminal() }
            }
        } else {
            // All sessions stay mounted (and their processes alive); only the
            // active one is visible/interactive. A ZStack keeps every emulator
            // sized so switching never reflows a cold terminal.
            ZStack {
                ForEach(workspace.terminals) { terminal in
                    let isActive = terminal.id == activeTerminal?.id
                    TerminalEmulatorView(
                        terminal: terminal,
                        font: preferences.terminalFont,
                        optionAsMeta: preferences.terminalOptionAsMeta,
                        isActive: isActive
                    )
                    .opacity(isActive ? 1 : 0)
                    .allowsHitTesting(isActive)
                }
            }
            .frame(minHeight: 160)
        }
    }
}

private struct TerminalSessionChip: View {
    let name: String
    let isActive: Bool
    let onSelect: () -> Void
    let onClose: () -> Void
    @State private var hovering = false

    var body: some View {
        HStack(spacing: 4) {
            Button(action: onSelect) {
                HStack(spacing: 4) {
                    Image(systemName: "terminal")
                        .font(.caption2)
                    Text(name)
                        .font(.caption)
                        .lineLimit(1)
                }
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Select terminal \(name)")
            Button(action: onClose) {
                Image(systemName: "trash")
                    .font(.caption2)
            }
            .buttonStyle(.borderless)
            .opacity(hovering || isActive ? 1 : 0)
            .help("Close \(name)")
            .accessibilityLabel("Close terminal \(name)")
        }
        .padding(.horizontal, 7)
        .padding(.vertical, 3)
        .background(
            RoundedRectangle(cornerRadius: 5)
                .fill(isActive ? Color.accentColor.opacity(0.22) : Color.secondary.opacity(hovering ? 0.14 : 0))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 5)
                .strokeBorder(isActive ? Color.accentColor.opacity(0.5) : .clear, lineWidth: 1)
        )
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
    }
}

private struct TerminalEmulatorView: NSViewRepresentable {
    @Bindable var terminal: TerminalController
    let font: NSFont
    let optionAsMeta: Bool
    let isActive: Bool

    func makeCoordinator() -> Coordinator {
        Coordinator(terminal: terminal)
    }

    func makeNSView(context: Context) -> LocalProcessTerminalView {
        let view = DroppableLocalProcessTerminalView(frame: .zero)
        view.font = font
        context.coordinator.appliedFont = font
        // Off by default so ⌥ produces layout characters (`@`, `{`, `|`, …) on
        // international keyboards instead of being hijacked as the Meta modifier.
        view.optionAsMetaKey = optionAsMeta
        view.configureNativeColors()
        view.nativeBackgroundColor = .textBackgroundColor
        view.nativeForegroundColor = .textColor
        view.caretColor = .controlAccentColor
        view.processDelegate = context.coordinator
        // Forward the scroll wheel to full-screen TUIs (Claude Code etc.) that
        // run on the alternate screen, which has no scrollback — see
        // TerminalScrollForwarder.
        TerminalScrollForwarder.installIfNeeded()
        // Layer-backed + opaque so AppKit composites the grid in one pass while
        // the panel is being dragged, instead of repainting through the window
        // background — that repaint is what made the terminal flicker on resize.
        view.wantsLayer = true
        view.layerContentsRedrawPolicy = .onSetNeedsDisplay
        context.coordinator.terminalView = view
        context.coordinator.installCursorRestoreMonitor()
        return view
    }

    static func dismantleNSView(_ view: LocalProcessTerminalView, coordinator: Coordinator) {
        coordinator.removeCursorRestoreMonitor()
        // The session was closed (or the panel hidden) — don't orphan the shell.
        if view.process.running {
            coordinator.suppressTermination = true
            view.terminate()
        }
    }

    func updateNSView(_ view: LocalProcessTerminalView, context: Context) {
        context.coordinator.terminal = terminal
        if context.coordinator.appliedFont != font {
            context.coordinator.appliedFont = font
            view.font = font
        }
        if view.optionAsMetaKey != optionAsMeta {
            view.optionAsMetaKey = optionAsMeta
        }
        if context.coordinator.restartToken != terminal.restartToken {
            let firstStart = context.coordinator.restartToken == nil
            context.coordinator.restartToken = terminal.restartToken
            if view.process.running {
                // The old process's async `processTerminated` would otherwise
                // flip `isRunning` to false right after we restarted.
                context.coordinator.suppressTermination = true
                view.terminate()
            }
            // A "New Shell" must be genuinely fresh: wipe the previous session's
            // screen, scrollback and terminal modes. A TUI like Claude Code hides
            // the cursor (DECTCEM `\e[?25l`); without a reset that state leaks
            // into the new shell and the caret stays invisible. `resetToInitial`
            // preserves `cursorHidden`, so we re-show it explicitly afterwards.
            if !firstStart {
                view.getTerminal().resetToInitialState()
                Coordinator.restoreBlinkingCaret(view)
                view.feed(text: "\u{1b}[?25h")
            }
            view.startProcess(
                executable: terminal.shellExecutable,
                args: terminal.shellArguments,
                environment: terminal.environmentVariables,
                execName: terminal.shellDisplayName,
                currentDirectory: terminal.currentDirectory.path
            )
            DispatchQueue.main.async {
                view.window?.makeFirstResponder(view)
            }
        }

        if let pendingInput = terminal.pendingInput,
           context.coordinator.lastInputID != pendingInput.id {
            context.coordinator.lastInputID = pendingInput.id
            let bytes = Array(pendingInput.text.utf8)
            view.process.send(data: ArraySlice(bytes))
            DispatchQueue.main.async {
                view.window?.makeFirstResponder(view)
            }
        }

        // When this session becomes the active one, hand it keyboard focus so
        // typing doesn't keep going to the now-hidden previous terminal.
        if isActive && !context.coordinator.wasActive {
            DispatchQueue.main.async {
                view.window?.makeFirstResponder(view)
            }
        }
        context.coordinator.wasActive = isActive
    }

    final class Coordinator: NSObject, LocalProcessTerminalViewDelegate {
        var terminal: TerminalController
        weak var terminalView: LocalProcessTerminalView?
        var restartToken: UUID?
        var lastInputID: UUID?
        var appliedFont: NSFont?
        /// Set right before a deliberate `terminate()` so the resulting
        /// `processTerminated` callback doesn't mark the controller as stopped.
        var suppressTermination = false
        var wasActive = false
        private var cursorMonitor: Any?

        init(terminal: TerminalController) {
            self.terminal = terminal
        }

        deinit {
            if let cursorMonitor { NSEvent.removeMonitor(cursorMonitor) }
        }

        /// A TUI such as Claude Code / Codex switches the caret to a steady
        /// DECSCUSR style and, when interrupted with Ctrl-C, often exits without
        /// restoring blinking — leaving a solid caret at the shell prompt.
        /// `keyDown` on the SwiftTerm view is `public`, not `open`, so we can't
        /// subclass it; a local key monitor re-asserts the blinking default a
        /// beat after the interrupt. The closure captures nothing non-Sendable —
        /// it targets whichever terminal holds focus when the key fires.
        func installCursorRestoreMonitor() {
            guard cursorMonitor == nil else { return }
            cursorMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
                guard event.modifierFlags.contains(.control),
                      event.charactersIgnoringModifiers?.lowercased() == "c"
                else { return event }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                    MainActor.assumeIsolated {
                        guard let view = NSApp.keyWindow?.firstResponder as? LocalProcessTerminalView
                        else { return }
                        Coordinator.restoreBlinkingCaret(view)
                    }
                }
                return event
            }
        }

        func removeCursorRestoreMonitor() {
            if let cursorMonitor { NSEvent.removeMonitor(cursorMonitor) }
            cursorMonitor = nil
        }

        /// Force the caret to blink again. `setCursorStyle` is a no-op when the
        /// style already equals the target, which doesn't restart the (stopped)
        /// blink animation — so we bounce through a steady style first.
        @MainActor
        static func restoreBlinkingCaret(_ view: LocalProcessTerminalView) {
            let term = view.getTerminal()
            term.setCursorStyle(.steadyBlock)
            term.setCursorStyle(.blinkBlock)
        }

        func sizeChanged(source: LocalProcessTerminalView, newCols: Int, newRows: Int) {}

        func setTerminalTitle(source: LocalProcessTerminalView, title: String) {
            Task { @MainActor [terminal] in
                terminal.title = title.isEmpty ? terminal.shellDisplayName : title
            }
        }

        func hostCurrentDirectoryUpdate(source: TerminalView, directory: String?) {
            guard let directory, !directory.isEmpty else { return }
            // Shells emit OSC 7 with a `file://host/path` URL. Parse it so we
            // don't end up storing the literal `file://…` string as a path.
            let resolvedPath: String
            if directory.hasPrefix("file://"), let url = URL(string: directory) {
                resolvedPath = url.path
            } else {
                resolvedPath = directory
            }
            Task { @MainActor [terminal] in
                terminal.currentDirectory = URL(fileURLWithPath: resolvedPath)
            }
        }

        func processTerminated(source: TerminalView, exitCode: Int32?) {
            if suppressTermination {
                suppressTermination = false
                return
            }
            Task { @MainActor [terminal] in
                terminal.markTerminated()
            }
        }
    }
}

/// Accepts Finder file and folder drops directly in the terminal instead of
/// letting the parent workspace drop destination open them in the editor.
private final class DroppableLocalProcessTerminalView: LocalProcessTerminalView {
    override init(frame: CGRect) {
        super.init(frame: frame)
        registerForDraggedTypes([.fileURL])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        droppedFileURLs(from: sender).isEmpty ? [] : .copy
    }

    override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation {
        droppedFileURLs(from: sender).isEmpty ? [] : .copy
    }

    override func prepareForDragOperation(_ sender: NSDraggingInfo) -> Bool {
        !droppedFileURLs(from: sender).isEmpty
    }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        let urls = droppedFileURLs(from: sender)
        guard !urls.isEmpty else { return false }

        // Focus first so subsequent typing stays in the terminal even when the
        // editor or sidebar owned first responder before the drop.
        window?.makeFirstResponder(self)
        let paths = urls.map { RunService.shellQuote($0.path) }.joined(separator: " ")
        send(txt: paths + " ")
        return true
    }

    private func droppedFileURLs(from sender: NSDraggingInfo) -> [URL] {
        let options: [NSPasteboard.ReadingOptionKey: Any] = [
            .urlReadingFileURLsOnly: true
        ]
        let objects = sender.draggingPasteboard.readObjects(
            forClasses: [NSURL.self],
            options: options
        )
        return (objects as? [URL]) ?? []
    }
}

/// Makes the scroll wheel work inside full-screen TUIs (Claude Code, htop, less…).
///
/// SwiftTerm's own `scrollWheel` only moves the *scrollback* of the normal
/// screen. Full-screen apps run on the **alternate screen**, which has no
/// scrollback, so the wheel does nothing there — and SwiftTerm never forwards
/// the wheel to the app either. Codex works because it stays on the normal
/// screen; Claude Code doesn't because it's on the alternate screen.
///
/// `scrollWheel` is `public` (not `open`) on the SwiftTerm view, so it can't be
/// overridden by subclassing. Instead a single app-wide local event monitor (the
/// same approach as the Ctrl-C caret monitor) intercepts wheel events over a
/// terminal that is on the alternate screen and forwards them to the program:
/// proper mouse-wheel events when the app enabled mouse reporting (Claude), or
/// cursor up/down as a fallback (matching iTerm2's behaviour). Events on the
/// normal screen are passed straight through so scrollback keeps working.
@MainActor
enum TerminalScrollForwarder {
    private static var installed = false
    /// Residual trackpad travel (points) carried between precise scroll events so
    /// a flick is metered into discrete line ticks instead of flooding the app.
    private static var preciseResidual: CGFloat = 0

    static func installIfNeeded() {
        guard !installed else { return }
        installed = true
        // The handler is `@Sendable`/nonisolated, so we read the (Sendable)
        // scalars off the event here and resolve the window/view on the main
        // actor — passing the `NSEvent` itself across that boundary isn't allowed.
        NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { event in
            let location = event.locationInWindow
            let precise = event.hasPreciseScrollingDeltas
            let scrollingDeltaY = event.scrollingDeltaY
            let deltaY = event.deltaY
            let consumed = MainActor.assumeIsolated {
                forward(locationInWindow: location, precise: precise, scrollingDeltaY: scrollingDeltaY, deltaY: deltaY)
            }
            return consumed ? nil : event
        }
    }

    /// Returns `true` when the scroll was forwarded to a TUI and should be
    /// consumed; `false` to let SwiftTerm handle it (normal-screen scrollback).
    private static func forward(locationInWindow: NSPoint, precise: Bool, scrollingDeltaY: CGFloat, deltaY: CGFloat) -> Bool {
        guard let root = NSApp.keyWindow?.contentView,
              let hit = root.hitTest(locationInWindow),
              let view = enclosingTerminalView(hit) else { return false }
        let terminal = view.getTerminal()
        // Normal screen → SwiftTerm scrolls its scrollback (works). Only the
        // alternate screen needs forwarding.
        guard terminal.isCurrentBufferAlternate else { return false }

        let (scrollUp, count) = lineTicks(precise: precise, scrollingDeltaY: scrollingDeltaY, deltaY: deltaY)
        guard count > 0 else { return true }

        if view.allowMouseReporting, terminal.mouseMode != .off {
            let (col, row) = gridLocation(in: view, locationInWindow: locationInWindow)
            // Button 4 = wheel up, 5 = wheel down; sendEvent encodes per the
            // app's active mouse protocol (SGR for modern TUIs).
            let flags = terminal.encodeButton(button: scrollUp ? 4 : 5, release: false, shift: false, meta: false, control: false)
            for _ in 0..<count { terminal.sendEvent(buttonFlags: flags, x: col, y: row) }
        } else {
            let arrow = scrollUp ? "\u{1b}[A" : "\u{1b}[B"
            view.send(txt: String(repeating: arrow, count: count))
        }
        return true
    }

    private static func enclosingTerminalView(_ view: NSView) -> LocalProcessTerminalView? {
        var current: NSView? = view
        while let node = current {
            if let terminal = node as? LocalProcessTerminalView { return terminal }
            current = node.superview
        }
        return nil
    }

    /// (scrollUp, lineCount). Positive wheel/trackpad travel reveals earlier
    /// content (scroll up); precise deltas are accumulated against a per-line
    /// threshold so trackpad scrolling stays smooth without overwhelming the app.
    private static func lineTicks(precise: Bool, scrollingDeltaY: CGFloat, deltaY: CGFloat) -> (up: Bool, count: Int) {
        if precise {
            preciseResidual += scrollingDeltaY
            let perLine: CGFloat = 16
            let ticks = Int(preciseResidual / perLine)
            if ticks != 0 { preciseResidual -= CGFloat(ticks) * perLine }
            return (ticks > 0, abs(ticks))
        }
        let lines = Int(abs(deltaY))
        return (deltaY > 0, min(max(lines, 1), 5))
    }

    /// 0-based grid cell under the pointer (what `sendEvent` expects).
    private static func gridLocation(in view: LocalProcessTerminalView, locationInWindow: NSPoint) -> (col: Int, row: Int) {
        let terminal = view.getTerminal()
        let cols = max(terminal.cols, 1)
        let rows = max(terminal.rows, 1)
        let local = view.convert(locationInWindow, from: nil)
        let cellWidth = view.bounds.width / CGFloat(cols)
        let cellHeight = view.bounds.height / CGFloat(rows)
        guard cellWidth > 0, cellHeight > 0 else { return (0, 0) }
        let col = min(max(Int(local.x / cellWidth), 0), cols - 1)
        let yFromTop = view.isFlipped ? local.y : (view.bounds.height - local.y)
        let row = min(max(Int(yFromTop / cellHeight), 0), rows - 1)
        return (col, row)
    }
}
