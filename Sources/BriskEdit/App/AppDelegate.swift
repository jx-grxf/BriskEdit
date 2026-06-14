import AppKit
import Darwin

enum AppRuntimeSafety {
    static func install() {
        // Process/FileHandle writes otherwise terminate the entire app when an
        // LSP, formatter, terminal, or IPC peer closes its pipe first.
        _ = signal(SIGPIPE, SIG_IGN)
    }
}

/// Installs a key-event guard that silences the macOS "funk" alert sound which
/// AppKit emits when a printable key is pressed while focus sits on a view that
/// can't accept text input (toolbar chrome, dividers, plain SwiftUI containers).
/// Text fields, the editor, the terminal, list navigation and shortcuts are all
/// left untouched.
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var keyMonitor: Any?

    func applicationWillFinishLaunching(_ notification: Notification) {
        AppRuntimeSafety.install()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            KeyEventGuard.shouldSwallow(event) ? nil : event
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        if let keyMonitor {
            NSEvent.removeMonitor(keyMonitor)
            self.keyMonitor = nil
        }
        // Kill any language servers we spawned so they don't outlive the app.
        LSPProcessRegistry.shared.terminateAll()
        // Clear our Discord Rich Presence so a stale card doesn't linger.
        DiscordPresenceController.shared.shutdown()
    }

    func application(_ sender: NSApplication, openFile filename: String) -> Bool {
        ExternalFileOpenCoordinator.shared.open([URL(fileURLWithPath: filename)])
        return true
    }

    func application(_ sender: NSApplication, openFiles filenames: [String]) {
        ExternalFileOpenCoordinator.shared.open(filenames.map { URL(fileURLWithPath: $0) })
        sender.reply(toOpenOrPrint: .success)
    }

    /// Right-click the Dock icon → "New Window". Routes through the SwiftUI
    /// `openWindow` action captured by a live window.
    func applicationDockMenu(_ sender: NSApplication) -> NSMenu? {
        let menu = NSMenu()
        let item = NSMenuItem(title: "New Window", action: #selector(newWindowFromDock), keyEquivalent: "")
        item.target = self
        menu.addItem(item)
        return menu
    }

    /// Let SwiftUI re-present the primary scene when the Dock icon is clicked
    /// with no visible windows. Requesting a secondary window here duplicates
    /// the system reopen: one restored primary plus one empty workspace.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        return true
    }

    @objc private func newWindowFromDock() {
        NewWindowCoordinator.shared.openNewWindow()
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        let dirty = WorkspaceRegistry.models.filter(\.hasUnsavedChanges)
        guard !dirty.isEmpty else { return .terminateNow }

        let alert = NSAlert()
        alert.messageText = "You have unsaved changes."
        alert.informativeText = "Do you want to save them before quitting?"
        alert.addButton(withTitle: "Save")
        alert.addButton(withTitle: "Discard")
        alert.addButton(withTitle: "Cancel")
        switch alert.runModal() {
        case .alertFirstButtonReturn:
            Task { @MainActor in
                var success = true
                for model in dirty where await model.saveAllForQuit() == false { success = false }
                sender.reply(toApplicationShouldTerminate: success)
            }
            return .terminateLater
        case .alertSecondButtonReturn:
            return .terminateNow
        default:
            return .terminateCancel
        }
    }
}

/// Tracks live workspaces so the app can check for unsaved changes on quit.
@MainActor
enum WorkspaceRegistry {
    private static let table = NSHashTable<WorkspaceModel>.weakObjects()

    static func register(_ model: WorkspaceModel) {
        table.add(model)
    }

    static var models: [WorkspaceModel] {
        table.allObjects
    }
}

enum KeyEventGuard {
    @MainActor
    static func shouldSwallow(_ event: NSEvent) -> Bool {
        // Never interfere with shortcuts (⌘/⌃ combos route through menus/bindings).
        if !event.modifierFlags.intersection([.command, .control]).isEmpty { return false }

        // Only printable characters cause the funk; leave navigation, activation
        // and editing keys (arrows, F-keys, space, return, tab, delete) alone.
        guard let characters = event.charactersIgnoringModifiers, characters.count == 1,
              let scalar = characters.unicodeScalars.first else { return false }
        let value = scalar.value
        let isFunctionKey = (0xF700...0xF8FF).contains(value)
        let isWhitespaceOrControl = value < 0x20 || value == 0x7F || value == 0x20
        guard !isFunctionKey, !isWhitespaceOrControl else { return false }

        // Allow the keystroke whenever focus is on something that takes text or
        // manages its own keyboard handling.
        guard let responder = NSApp.keyWindow?.firstResponder else { return true }
        return !acceptsKeyInput(responder)
    }

    @MainActor
    private static func acceptsKeyInput(_ responder: NSResponder) -> Bool {
        if responder is NSText || responder is NSTextView || responder is NSTextField || responder is NSTableView {
            return true
        }
        if responder.responds(to: NSSelectorFromString("insertText:")) { return true }
        let className = String(describing: type(of: responder))
        return className.contains("Terminal") || className.contains("TextView") || className.contains("OutlineView")
    }
}

/// Receives files opened through Finder / Launch Services and routes them into
/// the first live workspace once SwiftUI has created one.
@MainActor
final class ExternalFileOpenCoordinator {
    static let shared = ExternalFileOpenCoordinator()
    private var pendingURLs: [URL] = []

    private init() {}

    func open(_ urls: [URL]) {
        guard !urls.isEmpty else { return }
        if let workspace = WorkspaceRegistry.models.first {
            route(urls, into: workspace)
        } else {
            pendingURLs.append(contentsOf: urls)
            NewWindowCoordinator.shared.openNewWindow()
        }
    }

    func drainPending(into workspace: WorkspaceModel) {
        guard !pendingURLs.isEmpty else { return }
        let urls = pendingURLs
        pendingURLs.removeAll()
        route(urls, into: workspace)
    }

    /// Directories become the workspace root (so `briskedit .` / "Open With" on a
    /// folder opens a project), files open as tabs.
    private func route(_ urls: [URL], into workspace: WorkspaceModel) {
        let fm = FileManager.default
        for url in urls {
            var isDirectory: ObjCBool = false
            if fm.fileExists(atPath: url.path, isDirectory: &isDirectory), isDirectory.boolValue {
                workspace.setWorkspaceRoot(url)
            } else {
                Task { await workspace.openFile(at: url) }
            }
        }
    }
}
