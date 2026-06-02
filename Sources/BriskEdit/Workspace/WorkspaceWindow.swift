import AppKit
import SwiftUI

struct WorkspaceWindow: View {
    let kind: WindowKind
    @State private var workspace = WorkspaceModel()
    @State private var columnVisibility: NavigationSplitViewVisibility = .all
    @State private var didStartSession = false
    @Environment(Preferences.self) private var preferences
    @Environment(UpdateService.self) private var updates
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            sidebar
                .navigationSplitViewColumnWidth(min: 220, ideal: 260, max: 420)
        } detail: {
            detail
        }
        .navigationSplitViewStyle(.balanced)
        .task {
            guard !didStartSession else { return }
            didStartSession = true
            if kind.restoresSession {
                await workspace.startPrimarySession(restoreLastWorkspace: preferences.startupBehavior == .restoreLastWorkspace)
            }
        }
        .onAppear {
            NewWindowCoordinator.shared.open = { openWindow(value: WindowKind.secondary(UUID())) }
        }
        .background(WindowConfigurator(
            isPrimaryWindow: kind.restoresSession,
            isDocumentEdited: workspace.hasUnsavedChanges,
            hasUnsavedChanges: workspace.hasUnsavedChanges,
            saveAll: { await workspace.saveAllForQuit() }
        ))
        .toolbar {
            if updates.isUpdateAvailable {
                ToolbarItem(placement: .navigation) {
                    Button {
                        updates.checkForUpdates()
                    } label: {
                        Image(systemName: "arrow.down.circle.fill")
                    }
                    .tint(.blue)
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

    @ViewBuilder
    private var sidebar: some View {
        if let root = workspace.rootURL {
            VStack(spacing: 0) {
                Picker("Sidebar section", selection: Bindable(workspace).sidebarTab) {
                    Image(systemName: "folder").accessibilityLabel("Files").tag(SidebarTab.files)
                    Image(systemName: "magnifyingglass").accessibilityLabel("Search").tag(SidebarTab.search)
                    Image(systemName: "list.bullet.indent").accessibilityLabel("Outline").tag(SidebarTab.outline)
                    Image(systemName: "arrow.triangle.branch").accessibilityLabel("Source Control").tag(SidebarTab.sourceControl)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                Divider()
                sidebarPanes(root: root)
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
                Button("Open Folder…") { openFolder() }
            }
        }
    }

    private func sidebarPanes(root: URL) -> some View {
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

    private var detail: some View {
        EditorTabsView(workspace: workspace, onOpenFile: { openFile() })
            .environment(preferences)
            .dropDestination(for: URL.self) { urls, _ in
                workspace.openDropped(urls)
                return true
            }
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

/// Reflects unsaved state in the window's red close button (the macOS dot) and
/// intercepts window close to prompt for unsaved changes — without losing
/// SwiftUI's own window-delegate behavior (calls are forwarded to it).
private struct WindowConfigurator: NSViewRepresentable {
    let isPrimaryWindow: Bool
    let isDocumentEdited: Bool
    let hasUnsavedChanges: Bool
    let saveAll: () async -> Bool

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> NSView { NSView() }

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
            if !didApplyInitialFrame, let screen = window.screen ?? NSScreen.main {
                didApplyInitialFrame = true
                let frame = screen.visibleFrame.insetBy(dx: 18, dy: 18)
                window.setFrame(frame, display: true, animate: false)
            }
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
                .font(.body.weight(.semibold))
        }
        .buttonStyle(.borderedProminent)
        .tint(.green)
        .controlSize(.large)
        .disabled(!isRunnable)
        .keyboardShortcut("r", modifiers: .command)
        .help(isRunnable ? "Compile & run in terminal" : "Open a runnable file to enable Run")
    }
}
