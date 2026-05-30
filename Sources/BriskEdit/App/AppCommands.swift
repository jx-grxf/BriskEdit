import SwiftUI
import AppKit

struct AppCommands: Commands {
    let updates: UpdateService
    @FocusedValue(\.workspace) private var workspace
    @Environment(\.openWindow) private var openWindow

    var body: some Commands {
        CommandGroup(replacing: .newItem) {
            Button("New File") {
                workspace?.newUntitled()
            }
            .keyboardShortcut("n", modifiers: .command)

            Button("New Window") {
                openWindow(value: WindowKind.secondary(UUID()))
            }
            .keyboardShortcut("n", modifiers: [.command, .shift])

            Button("Open File…") {
                openFile()
            }
            .keyboardShortcut("o", modifiers: .command)

            Button("Open Folder…") {
                openFolder()
            }
            .keyboardShortcut("o", modifiers: [.command, .shift])

            Button("Close Folder") {
                workspace?.closeFolder()
            }
            .keyboardShortcut("w", modifiers: [.command, .shift])
            .disabled(workspace?.rootURL == nil)
        }

        CommandGroup(after: .saveItem) {
            Button("Save") {
                Task { await workspace?.saveActiveTab() }
            }
            .keyboardShortcut("s", modifiers: .command)
            .disabled(workspace?.activeTab == nil)
        }

        CommandMenu("Selection") {
            Button("Go to File…") {
                workspace?.showFileFinder = true
            }
            .keyboardShortcut("p", modifiers: .command)
            .disabled(workspace?.rootURL == nil)

            Button("Command Palette…") {
                workspace?.showCommandPalette = true
            }
            .keyboardShortcut("p", modifiers: [.command, .shift])
        }

        CommandMenu("Run") {
            Button("Run File") {
                workspace?.runActiveDocument()
            }
            .keyboardShortcut("r", modifiers: .command)
            .disabled(workspace?.activeTab?.document.language.isRunnable != true)

            Button("Check File") {
                Task { await workspace?.checkActiveDocument() }
            }
            .keyboardShortcut("b", modifiers: .command)
            .disabled(workspace?.activeTab == nil)

            Button("Show Tool Health") {
                workspace?.showToolHealth = true
            }

            Divider()

            Button("Toggle Terminal") {
                workspace?.showTerminal.toggle()
            }
            .keyboardShortcut("`", modifiers: .control)

            Button("Toggle Markdown Preview") {
                workspace?.showMarkdownPreview.toggle()
            }
            .keyboardShortcut("m", modifiers: [.command, .shift])
        }

        CommandGroup(after: .appInfo) {
            Button("Check for Updates…") {
                updates.checkForUpdates()
            }
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
            Task { await workspace?.openFile(at: url) }
        }
    }

    @MainActor
    private func openFolder() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        workspace?.setWorkspaceRoot(url)
    }
}

private struct WorkspaceFocusedKey: FocusedValueKey {
    typealias Value = WorkspaceModel
}

extension FocusedValues {
    var workspace: WorkspaceModel? {
        get { self[WorkspaceFocusedKey.self] }
        set { self[WorkspaceFocusedKey.self] = newValue }
    }
}
