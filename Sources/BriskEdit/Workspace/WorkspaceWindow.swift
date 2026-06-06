import AppKit
import SwiftUI

struct WorkspaceWindow: View {
    let kind: WindowKind
    @State private var workspace = WorkspaceModel()
    @State private var columnVisibility: NavigationSplitViewVisibility = .all
    @State private var didStartSession = false
    @State private var secretBanner: String?
    @Environment(Preferences.self) private var preferences
    @Environment(UpdateService.self) private var updates
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            WorkspaceSidebar(workspace: workspace, openFolder: openFolder)
                .navigationSplitViewColumnWidth(min: 220, ideal: 260, max: 420)
        } detail: {
            WorkspaceDetail(workspace: workspace, onOpenFile: openFile)
        }
        .navigationSplitViewStyle(.balanced)
        .task {
            guard !didStartSession else { return }
            didStartSession = true
            if kind.restoresSession {
                await workspace.startPrimarySession(restoreLastWorkspace: preferences.startupBehavior == .restoreLastWorkspace)
            }
            ExternalFileOpenCoordinator.shared.drainPending(into: workspace)
        }
        .onAppear {
            NewWindowCoordinator.shared.open = { openWindow(value: WindowKind.secondary(UUID())) }
        }
        .onOpenURL { url in
            Task { await workspace.openFile(at: url) }
        }
        .background(WindowConfigurator(
            isPrimaryWindow: kind.restoresSession,
            isDocumentEdited: workspace.hasUnsavedChanges,
            hasUnsavedChanges: workspace.hasUnsavedChanges,
            saveAll: { await workspace.saveAllForQuit() }
        ))
        .overlay(alignment: .top) {
            if let banner = secretBanner {
                HStack(spacing: 10) {
                    Image(systemName: "sparkles")
                    Text(banner).font(.callout.weight(.medium))
                    if SecretMode.isEnabled {
                        Button("Deactivate") {
                            SecretMode.isEnabled = false
                            showSecretBanner("Secret deactivated")
                        }
                        .controlSize(.small)
                    }
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 9)
                .background(.ultraThinMaterial, in: Capsule())
                .overlay(Capsule().strokeBorder(.white.opacity(0.12)))
                .shadow(radius: 8, y: 2)
                .padding(.top, 12)
                .transition(.move(edge: .top).combined(with: .opacity))
                .task(id: banner) {
                    try? await Task.sleep(for: .seconds(2.6))
                    withAnimation { secretBanner = nil }
                }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .briskEditTitleSecret)) { note in
            if let message = note.userInfo?["message"] as? String { showSecretBanner(message) }
        }
        .toolbar {
            if updates.isUpdateAvailable {
                ToolbarItem(placement: .navigation) {
                    Button {
                        updates.checkForUpdates()
                    } label: {
                        Image(systemName: "arrow.down.circle.fill")
                    }
                    .tint(.blue)
                    .accessibilityLabel("Install update")
                    .help("Update available: BriskEdit \(updates.availableUpdateVersion ?? ""). Click to install.")
                }
            }
            ToolbarItemGroup(placement: .primaryAction) {
                Button("Toggle Terminal", systemImage: "terminal") {
                    workspace.toggleTerminal()
                }
                .labelStyle(.iconOnly)
                .help("Toggle terminal")

                RunButton(workspace: workspace)
            }
        }
        .task(id: discordActivity) {
            DiscordPresenceController.shared.update(discordActivity)
        }
        .focusedSceneValue(\.workspace, workspace)
        .sheet(isPresented: Bindable(workspace).showCommandPalette) {
            CommandPaletteView(workspace: workspace)
        }
        .sheet(isPresented: Bindable(workspace).showFileFinder) {
            FileFinderView(workspace: workspace)
        }
        .sheet(isPresented: Bindable(workspace).showToolHealth) {
            ToolHealthPanel()
        }
        .alert("BriskEdit", isPresented: Binding(
            get: { workspace.lastError != nil },
            set: { if !$0 { workspace.lastError = nil } }
        )) {
            Button("OK", role: .cancel) { workspace.lastError = nil }
        } message: {
            Text(workspace.lastError ?? "")
        }
    }

    /// Current Discord Rich Presence snapshot for this window. Computed in the
    /// view body so SwiftUI tracks the active tab / language / root and re-runs
    /// the `.task(id:)` whenever any of them changes.
    private var discordActivity: DiscordActivity {
        DiscordActivity.make(workspace: workspace, preferences: preferences)
    }

    private func showSecretBanner(_ message: String) {
        withAnimation { secretBanner = message }
    }

    @MainActor
    private func openFile() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = true
        guard panel.runModal() == .OK else { return }
        for url in panel.urls {
            Task { await workspace.openFile(at: url) }
        }
    }

    @MainActor
    private func openFolder() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        guard panel.runModal() == .OK, let url = panel.url else { return }
        workspace.setWorkspaceRoot(url)
    }
}

/// The navigation column: the segmented section picker over the four sidebar
/// panes, or an empty state inviting the user to open a folder.
private struct WorkspaceSidebar: View {
    @Bindable var workspace: WorkspaceModel
    let openFolder: () -> Void

    var body: some View {
        if let root = workspace.rootURL {
            VStack(spacing: 0) {
                Picker("Sidebar section", selection: $workspace.sidebarTab) {
                    Image(systemName: "folder").accessibilityLabel("Files").tag(SidebarTab.files)
                    Image(systemName: "magnifyingglass").accessibilityLabel("Search").tag(SidebarTab.search)
                    Image(systemName: "list.bullet.indent").accessibilityLabel("Outline").tag(SidebarTab.outline)
                    Image(systemName: "arrow.triangle.branch").accessibilityLabel("Source Control").tag(SidebarTab.sourceControl)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .padding(.horizontal, 10)
                .padding(.vertical, DesignTokens.Spacing.small)
                Divider()
                WorkspaceSidebarPanes(workspace: workspace, root: root)
            }
            // Pin to the top and fill the column — otherwise a short pane (empty
            // search, "No symbols" outline) lets the whole stack center itself and
            // leaves a gap above the tab picker.
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .navigationTitle(root.lastPathComponent)
        } else {
            ContentUnavailableView {
                Label("No Folder Open", systemImage: "folder.badge.questionmark")
            } description: {
                Text("Open a folder to browse files.")
            } actions: {
                Button("Open Folder…", action: openFolder)
            }
        }
    }
}

/// The four sidebar panes overlaid in a `ZStack`; only the selected one is
/// visible/hittable so each keeps its own scroll position across switches.
private struct WorkspaceSidebarPanes: View {
    @Bindable var workspace: WorkspaceModel
    let root: URL

    var body: some View {
        ZStack {
            FileTreeView(root: root, workspace: workspace)
                .visibleSidebarPane(workspace.sidebarTab == .files)
            SearchSidebarView(workspace: workspace)
                .visibleSidebarPane(workspace.sidebarTab == .search)
            OutlineSidebarView(workspace: workspace)
                .visibleSidebarPane(workspace.sidebarTab == .outline)
            GitSidebarView(workspace: workspace, root: root)
                .visibleSidebarPane(workspace.sidebarTab == .sourceControl)
        }
    }
}

/// The detail column: the editor/tabs surface, with folder drops opening files.
private struct WorkspaceDetail: View {
    @Bindable var workspace: WorkspaceModel
    let onOpenFile: () -> Void
    @Environment(Preferences.self) private var preferences

    var body: some View {
        EditorTabsView(workspace: workspace, onOpenFile: onOpenFile)
            .environment(preferences)
            .dropDestination(for: URL.self) { urls, _ in
                workspace.openDropped(urls)
                return true
            }
    }
}

/// Reflects unsaved state in the window's red close button (the macOS dot) and
/// intercepts window close to prompt for unsaved changes — without losing
/// SwiftUI's own window-delegate behavior (calls are forwarded to it).
private struct WindowConfigurator: NSViewRepresentable {
    let isPrimaryWindow: Bool
    let isDocumentEdited: Bool
    let hasUnsavedChanges: Bool
    let saveAll: () async -> Bool

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> NSView {
        let view = WindowAttachingView()
        // Configure as soon as the backing view actually joins a window. Doing
        // this only from `updateNSView` was unreliable: at launch that runs while
        // `view.window` is still nil, so the full-size frame was never applied and
        // the window opened at SwiftUI's small default size.
        view.onMoveToWindow = { [weak coordinator = context.coordinator] window in
            let edited = isDocumentEdited
            let hasUnsaved = hasUnsavedChanges
            let isPrimary = isPrimaryWindow
            let save = saveAll
            DispatchQueue.main.async {
                coordinator?.configure(window: window, isPrimaryWindow: isPrimary, isEdited: edited, hasUnsaved: hasUnsaved, saveAll: save)
            }
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        let coordinator = context.coordinator
        let edited = isDocumentEdited
        let hasUnsaved = hasUnsavedChanges
        let isPrimary = isPrimaryWindow
        let save = saveAll
        DispatchQueue.main.async {
            coordinator.configure(window: nsView.window, isPrimaryWindow: isPrimary, isEdited: edited, hasUnsaved: hasUnsaved, saveAll: save)
        }
    }

    @MainActor
    final class Coordinator: NSObject, NSWindowDelegate {
        private weak var window: NSWindow?
        private weak var forwardee: NSWindowDelegate?
        private var hasUnsaved = false
        private var saveAll: () async -> Bool = { true }
        private var didApplyInitialFrame = false

        func configure(window: NSWindow?, isPrimaryWindow: Bool, isEdited: Bool, hasUnsaved: Bool, saveAll: @escaping () async -> Bool) {
            guard let window else { return }
            // We restore the folder + open tabs ourselves (startPrimarySession).
            // Letting AppKit *also* persist/restore this window produces a second,
            // duplicate window on cold start ("a new empty one + the old folder").
            // Opting out of system restoration leaves our own restore as the only
            // path, so exactly one window comes back.
            window.isRestorable = false
            if isPrimaryWindow, !PrimaryWindowRegistry.shared.claim(window) {
                DispatchQueue.main.async { window.close() }
                return
            }
            self.window = window
            self.hasUnsaved = hasUnsaved
            self.saveAll = saveAll
            window.isDocumentEdited = isEdited
            if window.delegate !== self {
                forwardee = window.delegate
                window.delegate = self
            }
            if !didApplyInitialFrame {
                didApplyInitialFrame = true
                enforceFullSizeFrame(on: window)
            }
            installTitleClickHook(on: window)
        }

        /// SwiftUI resizes the window to its content's ideal size *after* our first
        /// pass, and the exact moment varies — a single re-apply (or even two)
        /// loses that race and the window opens small. Re-apply across a ~1.2s
        /// settling window so we win regardless of when SwiftUI settles;
        /// `applyFullSizeFrame` is a no-op once the frame already matches, so this
        /// stops touching the window the instant it's correct.
        private func enforceFullSizeFrame(on window: NSWindow) {
            let delays: [Double] = [0, 0.05, 0.12, 0.25, 0.4, 0.6, 0.85, 1.2]
            for delay in delays {
                if delay == 0 {
                    applyFullSizeFrame(to: window)
                } else {
                    DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self, weak window] in
                        guard let self, let window else { return }
                        self.applyFullSizeFrame(to: window)
                    }
                }
            }
        }

        private func applyFullSizeFrame(to window: NSWindow) {
            guard let screen = window.screen ?? NSScreen.main ?? NSScreen.screens.first else { return }
            let target = screen.visibleFrame
            // Already flush full-size — don't fight a settled (or user-resized)
            // window. Compare *origin too*: `defaultSize` can match the size while
            // SwiftUI centers the window, so a size-only check skipped the
            // reposition and left uneven margins.
            let frame = window.frame
            if abs(frame.width - target.width) < 2, abs(frame.height - target.height) < 2,
               abs(frame.origin.x - target.origin.x) < 2, abs(frame.origin.y - target.origin.y) < 2 {
                return
            }
            window.setFrame(target, display: true, animate: false)
        }

        // MARK: - Title click hook

        private var titleClickCount = 0
        private var didInstallTitleHook = false

        /// Attaches a click recognizer to the existing window title so the title
        /// stays the single one in the bar (no extra toolbar item). The title
        /// label only exists after the toolbar lays out, so retry briefly.
        private func installTitleClickHook(on window: NSWindow, attempt: Int = 0) {
            guard !didInstallTitleHook else { return }
            guard let label = Self.titleLabel(in: window) else {
                guard attempt < 6 else { return }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { [weak self, weak window] in
                    guard let self, let window else { return }
                    self.installTitleClickHook(on: window, attempt: attempt + 1)
                }
                return
            }
            didInstallTitleHook = true
            let recognizer = NSClickGestureRecognizer(target: self, action: #selector(handleTitleClick))
            recognizer.numberOfClicksRequired = 1
            label.addGestureRecognizer(recognizer)
        }

        @objc private func handleTitleClick() {
            titleClickCount += 1
            guard titleClickCount >= 5 else { return }
            titleClickCount = 0
            SecretMode.isEnabled.toggle()
            let message = SecretMode.isEnabled ? "Secret activated" : "Secret deactivated"
            NotificationCenter.default.post(name: .briskEditTitleSecret, object: nil, userInfo: ["message": message])
        }

        /// Finds the titlebar's title label — the first non-editable text field
        /// inside the titlebar container (reached via the traffic-light button's
        /// superview), so the search can't stray into the window content.
        private static func titleLabel(in window: NSWindow) -> NSView? {
            guard let titlebar = window.standardWindowButton(.closeButton)?.superview else { return nil }
            return firstStaticTextField(in: titlebar)
        }

        private static func firstStaticTextField(in view: NSView) -> NSTextField? {
            if let field = view as? NSTextField, !field.isEditable, !(field is NSSearchField) {
                return field
            }
            for subview in view.subviews {
                if let found = firstStaticTextField(in: subview) { return found }
            }
            return nil
        }

        func windowShouldClose(_ sender: NSWindow) -> Bool {
            guard hasUnsaved else { return true }
            let alert = NSAlert()
            alert.messageText = "You have unsaved changes."
            alert.informativeText = "Do you want to save them before closing?"
            alert.addButton(withTitle: "Save")
            alert.addButton(withTitle: "Don't Save")
            alert.addButton(withTitle: "Cancel")
            switch alert.runModal() {
            case .alertFirstButtonReturn:
                let save = saveAll
                Task { @MainActor in
                    if await save() { sender.close() }
                }
                return false
            case .alertSecondButtonReturn:
                return true
            default:
                return false
            }
        }

        override func responds(to aSelector: Selector!) -> Bool {
            if super.responds(to: aSelector) { return true }
            return forwardee?.responds(to: aSelector) ?? false
        }

        override func forwardingTarget(for aSelector: Selector!) -> Any? {
            if let forwardee, forwardee.responds(to: aSelector) { return forwardee }
            return super.forwardingTarget(for: aSelector)
        }
    }
}

extension Notification.Name {
    /// Posted when the window title's hidden toggle fires; carries a "message".
    static let briskEditTitleSecret = Notification.Name("briskEditTitleSecret")
}

/// A zero-size helper view that reports when it is attached to (or detached
/// from) a window, so the configurator can set up the window the moment it
/// becomes available — instead of polling from `updateNSView`.
private final class WindowAttachingView: NSView {
    var onMoveToWindow: ((NSWindow?) -> Void)?

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        onMoveToWindow?(window)
    }
}

@MainActor
private final class PrimaryWindowRegistry {
    static let shared = PrimaryWindowRegistry()
    private weak var primaryWindow: NSWindow?

    private init() {}

    func claim(_ window: NSWindow) -> Bool {
        if let primaryWindow, primaryWindow !== window, primaryWindow.isVisible {
            return false
        }
        primaryWindow = window
        return true
    }
}

private extension View {
    func visibleSidebarPane(_ isVisible: Bool) -> some View {
        opacity(isVisible ? 1 : 0)
            .allowsHitTesting(isVisible)
            .accessibilityHidden(!isVisible)
            .animation(.easeInOut(duration: 0.12), value: isVisible)
    }
}

/// Prominent green Run button for the window toolbar — compiles/runs the active
/// document in the integrated terminal.
private struct RunButton: View {
    @Bindable var workspace: WorkspaceModel

    private var isRunnable: Bool {
        workspace.activeTab?.document.language.isRunnable == true
    }

    var body: some View {
        Button {
            workspace.runActiveDocument()
        } label: {
            Label("Run", systemImage: "play.fill")
        }
        .buttonStyle(.borderedProminent)
        .tint(.green)
        .controlSize(.regular)
        .disabled(!isRunnable)
        .keyboardShortcut("r", modifiers: .command)
        .help(isRunnable ? "Compile & run in terminal" : "Open a runnable file to enable Run")
    }
}
