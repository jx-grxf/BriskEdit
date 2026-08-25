import Foundation

@MainActor
struct EditorCommand: Identifiable, Hashable {
    let id: String
    let title: String
    let group: String
    let shortcut: String?
    let perform: (WorkspaceModel) -> Void

    nonisolated static func == (lhs: EditorCommand, rhs: EditorCommand) -> Bool { lhs.id == rhs.id }
    nonisolated func hash(into hasher: inout Hasher) { hasher.combine(id) }
}

@MainActor
enum CommandRegistry {
    static let all: [EditorCommand] = [
        EditorCommand(id: "file.new", title: "New File", group: "File", shortcut: "⌘N") { ws in
            ws.newUntitled()
        },
        EditorCommand(id: "file.save", title: "Save", group: "File", shortcut: "⌘S") { ws in
            Task { await ws.saveActiveTab() }
        },
        EditorCommand(id: "file.saveAs", title: "Save As…", group: "File", shortcut: "⇧⌘S") { ws in
            Task { await ws.saveActiveTabAs() }
        },
        EditorCommand(id: "tab.closeActive", title: "Close Tab", group: "Tabs", shortcut: "⌃⌘W") { ws in
            if let id = ws.activeTabID { ws.requestCloseTab(id) }
        },
        EditorCommand(id: "tab.reopen", title: "Reopen Closed Tab", group: "Tabs", shortcut: "⇧⌘T") { ws in
            ws.reopenClosedTab()
        },
        EditorCommand(id: "file.goto", title: "Go to File…", group: "File", shortcut: "⌘P") { ws in
            ws.showFileFinder = true
        },
        EditorCommand(id: "search.inFiles", title: "Find in Files…", group: "Search", shortcut: "⇧⌘F") { ws in
            ws.revealSearch()
        },
        EditorCommand(id: "run.active", title: "Run File", group: "Run", shortcut: "⌘R") { ws in
            ws.runActiveDocument()
        },
        EditorCommand(id: "run.check", title: "Check File", group: "Run", shortcut: "⌘B") { ws in
            Task { await ws.checkActiveDocument() }
        },
        EditorCommand(id: "tools.health", title: "Show Tool Health", group: "Tools", shortcut: nil) { ws in
            ws.showToolHealth = true
        },
        EditorCommand(id: "terminal.toggle", title: "Toggle Terminal", group: "View", shortcut: "⌃`") { ws in
            ws.toggleTerminal()
        },
        EditorCommand(id: "terminal.new", title: "New Terminal", group: "View", shortcut: "⇧⌃`") { ws in
            ws.openNewTerminal()
        },
        EditorCommand(id: "markdown.toggle", title: "Toggle Markdown Preview", group: "View", shortcut: nil) { ws in
            ws.showMarkdownPreview.toggle()
        },
        EditorCommand(id: "files.refresh", title: "Refresh File Tree", group: "View", shortcut: nil) { ws in
            ws.refreshFileTree()
        }
    ]

    static func filtered(_ query: String) -> [EditorCommand] {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !q.isEmpty else { return all }
        return all.filter { $0.title.lowercased().contains(q) || $0.group.lowercased().contains(q) }
    }
}
