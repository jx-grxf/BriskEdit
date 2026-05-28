import SwiftUI

struct WorkspaceWindow: View {
    @State private var workspace = WorkspaceModel()
    @Environment(Preferences.self) private var preferences

    var body: some View {
        NavigationSplitView {
            sidebar
                .frame(minWidth: 220)
        } detail: {
            detail
        }
        .navigationSplitViewStyle(.balanced)
        .focusedSceneValue(\.workspace, workspace)
        .sheet(isPresented: Bindable(workspace).showCommandPalette) {
            CommandPaletteView(workspace: workspace)
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
            FileTreeView(root: root, workspace: workspace)
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

    @ViewBuilder
    private var detail: some View {
        if workspace.tabs.isEmpty {
            ContentUnavailableView {
                Label("BriskEdit", systemImage: "text.cursor")
            } description: {
                Text("Open a file or create a new document.")
            } actions: {
                HStack {
                    Button("New File") { workspace.newUntitled() }
                        .keyboardShortcut("n", modifiers: .command)
                    Button("Open File…") { openFile() }
                }
            }
        } else {
            EditorTabsView(workspace: workspace)
                .environment(preferences)
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
