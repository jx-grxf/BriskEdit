import SwiftUI
import AppKit

struct AppCommands: Commands {
    let updates: UpdateService
    @Bindable var preferences: Preferences
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

            Menu("Open Recent") {
                let folders = RecentWorkspacesStore.shared.folders
                if folders.isEmpty {
                    Button("No Recent Folders") {}.disabled(true)
                } else {
                    ForEach(folders, id: \.self) { url in
                        Button(url.lastPathComponent) { openRecent(url) }
                            .help(url.path)
                    }
                    Divider()
                    Button("Clear Menu") { RecentWorkspacesStore.shared.clear() }
                }
            }

            Button("Close Folder") {
                workspace?.closeFolder()
            }
            .keyboardShortcut("w", modifiers: [.command, .shift])
            .disabled(workspace?.rootURL == nil)

            Divider()

            Button("Close Tab") {
                if let id = workspace?.activeTabID { workspace?.requestCloseTab(id) }
            }
            .keyboardShortcut("w", modifiers: [.command, .control])
            .disabled(workspace?.activeTab == nil)

            Button("Close Other Tabs") {
                if let id = workspace?.activeTabID { workspace?.requestCloseOtherTabs(keeping: id) }
            }
            .disabled((workspace?.tabs.count ?? 0) < 2)

            Button("Close All Tabs") {
                workspace?.requestCloseAllTabs()
            }
            .disabled(workspace?.tabs.isEmpty != false)

            Divider()

            Button("Move Tab Left") {
                workspace?.moveActiveTab(by: -1)
            }
            .keyboardShortcut(.leftArrow, modifiers: [.command, .control])
            .disabled((workspace?.tabs.count ?? 0) < 2)

            Button("Move Tab Right") {
                workspace?.moveActiveTab(by: 1)
            }
            .keyboardShortcut(.rightArrow, modifiers: [.command, .control])
            .disabled((workspace?.tabs.count ?? 0) < 2)
        }

        CommandGroup(after: .saveItem) {
            Button("Save") {
                Task { await workspace?.saveActiveTab() }
            }
            .keyboardShortcut("s", modifiers: .command)
            .disabled(workspace?.activeTab == nil)

            Button("Save As…") {
                Task { await workspace?.saveActiveTabAs() }
            }
            .keyboardShortcut("s", modifiers: [.command, .shift])
            .disabled(workspace?.activeTab == nil)

            Button("Save All") {
                Task { _ = await workspace?.saveAllForQuit() }
            }
            .keyboardShortcut("s", modifiers: [.command, .option])
            .disabled(workspace?.hasUnsavedChanges != true)
        }

        CommandMenu("Go") {
            Button("Go to File…") {
                workspace?.showFileFinder = true
            }
            .keyboardShortcut("p", modifiers: .command)
            .disabled(workspace?.rootURL == nil)

            Button("Command Palette…") {
                workspace?.showCommandPalette = true
            }
            .keyboardShortcut("p", modifiers: [.command, .shift])

            Button("Find in Files…") {
                workspace?.revealSearch()
            }
            .keyboardShortcut("f", modifiers: [.command, .shift])
            .disabled(workspace?.rootURL == nil)
        }

        // Add to the *existing* system "View" menu (sidebar/toolbar group) rather
        // than declaring a second `CommandMenu("View")`, which produced two
        // separate "View" menus in the menu bar.
        CommandGroup(after: .toolbar) {
            Divider()
            Button("Increase Font Size") {
                preferences.adjustFontSize(by: 1)
            }
            .keyboardShortcut("=", modifiers: .command)

            Button("Decrease Font Size") {
                preferences.adjustFontSize(by: -1)
            }
            .keyboardShortcut("-", modifiers: .command)

            Button("Actual Size") {
                preferences.resetFontSize()
            }
            .keyboardShortcut("0", modifiers: .command)

            Divider()

            Toggle("Show Minimap", isOn: $preferences.showMinimap)
                .keyboardShortcut("m", modifiers: [.command, .control])

            Toggle("Show Hover Documentation", isOn: $preferences.showHoverTooltips)

            Toggle("Show Code Folding Controls", isOn: $preferences.showCodeFolding)

            Toggle("Show Git Change Bars", isOn: $preferences.showGitGutter)
                .disabled(!preferences.sourceControlEnabled)

            Button("Toggle Markdown Preview") {
                workspace?.showMarkdownPreview.toggle()
            }
            .keyboardShortcut("m", modifiers: [.command, .shift])
            .disabled(workspace?.activeTab?.document.language != .markdown)

            Menu("Theme") {
                Picker("Theme", selection: $preferences.themeID) {
                    ForEach(ThemeStore.shared.themes) { theme in
                        Text(theme.name).tag(theme.id)
                    }
                }
                .pickerStyle(.inline)
            }

            Menu("Performance Mode") {
                Picker("Performance Mode", selection: $preferences.performanceMode) {
                    ForEach(Preferences.PerformanceMode.allCases) { mode in
                        Label(mode.title, systemImage: mode.systemImage).tag(mode)
                    }
                }
                .pickerStyle(.inline)
            }

            Menu("Language") {
                if let doc = workspace?.activeTab?.document {
                    LanguageMenuItems(document: doc)
                }
            }
            .disabled(workspace?.activeTab?.document == nil)
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

        }

        CommandMenu("Terminal") {
            Button("New Terminal") {
                workspace?.openNewTerminal()
            }
            .keyboardShortcut("`", modifiers: [.control, .shift])
            .disabled(workspace == nil)

            Button(workspace?.showTerminal == true ? "Hide Terminal" : "Show Terminal") {
                workspace?.toggleTerminal()
            }
            .keyboardShortcut("`", modifiers: .control)
            .disabled(workspace == nil)

            Divider()

            Button("Clear Terminal") {
                workspace?.activeTerminal?.clear()
            }
            .disabled(workspace?.activeTerminal == nil)

            Button("Close Terminal Session") {
                workspace?.closeActiveTerminal()
            }
            .keyboardShortcut("w", modifiers: [.control, .shift])
            .disabled(workspace?.activeTerminal == nil)
        }

        CommandGroup(after: .appInfo) {
            Button("Check for Updates…") {
                updates.checkForUpdates()
            }
        }

        // Replace the default "BriskEdit Help" item (which only shows an
        // "Help isn't available" alert) with a link to the project on GitHub.
        CommandGroup(replacing: .help) {
            Button("What's New in BriskEdit") {
                workspace?.showWhatsNew(version: WhatsNew.currentVersion)
            }
            .disabled(workspace == nil)
            Button("BriskEdit on GitHub") {
                if let url = URL(string: "https://github.com/jx-grxf/BriskEdit") {
                    NSWorkspace.shared.open(url)
                }
            }
        }
    }

    @MainActor
    private func openRecent(_ url: URL) {
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory), isDirectory.boolValue else {
            NSSound.beep()
            return
        }
        if let workspace {
            workspace.setWorkspaceRoot(url)
        } else {
            openWindow(value: WindowKind.secondary(UUID()))
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
