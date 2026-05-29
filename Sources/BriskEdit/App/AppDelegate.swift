import AppKit

/// Installs a key-event guard that silences the macOS "funk" alert sound which
/// AppKit emits when a printable key is pressed while focus sits on a view that
/// can't accept text input (toolbar chrome, dividers, plain SwiftUI containers).
/// Text fields, the editor, the terminal, list navigation and shortcuts are all
/// left untouched.
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var keyMonitor: Any?

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
