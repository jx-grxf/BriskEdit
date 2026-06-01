import AppKit
import SwiftUI

struct WorkspaceWindow: View {
    let kind: WindowKind
    @State private var workspace = WorkspaceModel()
    @State private var columnVisibility: NavigationSplitViewVisibility = .all
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
            if kind.restoresSession { await workspace.restoreWorkspace() }
        }
        .onAppear {
            NewWindowCoordinator.shared.open = { openWindow(value: WindowKind.secondary(UUID())) }
        }
        .background(WindowConfigurator(
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
                Button {
                    workspace.toggleTerminal()
                } label: {
                    Image(systemName: "terminal")
                }
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
                Picker("", selection: Bindable(workspace).sidebarTab) {
                    Image(systemName: "folder").tag(SidebarTab.files)
                    Image(systemName: "magnifyingglass").tag(SidebarTab.search)
                    Image(systemName: "list.bullet.indent").tag(SidebarTab.outline)
                    Image(systemName: "arrow.triangle.branch").tag(SidebarTab.sourceControl)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                Divider()
                switch workspace.sidebarTab {
                case .files:
                    FileTreeView(root: root, workspace: workspace)
                case .search:
                    SearchSidebarView(workspace: workspace)
                case .outline:
                    OutlineSidebarView(workspace: workspace)
                case .sourceControl:
                    GitSidebarView(workspace: workspace, root: root)
                }
            }
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
    let isDocumentEdited: Bool
    let hasUnsavedChanges: Bool
    let saveAll: () async -> Bool

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> NSView { NSView() }

    func updateNSView(_ nsView: NSView, context: Context) {
        let coordinator = context.coordinator
        let edited = isDocumentEdited
        let hasUnsaved = hasUnsavedChanges
        let save = saveAll
        DispatchQueue.main.async {
            coordinator.configure(window: nsView.window, isEdited: edited, hasUnsaved: hasUnsaved, saveAll: save)
        }
    }

    @MainActor
    final class Coordinator: NSObject, NSWindowDelegate {
        private weak var window: NSWindow?
        private weak var forwardee: NSWindowDelegate?
        private var hasUnsaved = false
        private var saveAll: () async -> Bool = { true }

        func configure(window: NSWindow?, isEdited: Bool, hasUnsaved: Bool, saveAll: @escaping () async -> Bool) {
            guard let window else { return }
            self.window = window
            self.hasUnsaved = hasUnsaved
            self.saveAll = saveAll
            window.isDocumentEdited = isEdited
            if window.delegate !== self {
                forwardee = window.delegate
                window.delegate = self
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
