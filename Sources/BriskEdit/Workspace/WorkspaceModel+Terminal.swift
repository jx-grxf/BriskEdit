import Foundation

// Integrated terminal sessions (a multi-shell panel).
extension WorkspaceModel {
    /// Whether the terminal panel should be rendered. It only makes sense inside
    /// a workspace context (a folder, an open file, or an explicitly created
    /// shell), so the bare welcome screen stays clean.
    var showsTerminalPanel: Bool {
        showTerminal && (rootURL != nil || activeTab != nil || !terminals.isEmpty)
    }

    /// Keep existing terminal views mounted when the panel is hidden so shell
    /// processes and scrollback survive a simple hide/show cycle.
    var shouldMountTerminalPanel: Bool {
        showsTerminalPanel || !terminals.isEmpty
    }

    func toggleTerminal() {
        showTerminal.toggle()
        if showTerminal { ensureTerminal() }
    }

    func hideTerminal() {
        showTerminal = false
    }

    /// Reveals the terminal and adds a fresh shell session.
    func openNewTerminal() {
        showTerminal = true
        addTerminal()
    }

    /// Closes the active shell; hides the panel when the last one is gone.
    func closeActiveTerminal() {
        guard let id = activeTerminal?.id else { return }
        closeTerminal(id)
        if terminals.isEmpty { showTerminal = false }
    }

    var activeTerminal: TerminalController? {
        if let id = activeTerminalID, let match = terminals.first(where: { $0.id == id }) {
            return match
        }
        return terminals.first
    }

    /// Returns the active session, creating the first one on demand.
    @discardableResult
    func ensureTerminal() -> TerminalController {
        if let active = activeTerminal { return active }
        return addTerminal()
    }

    @discardableResult
    func addTerminal() -> TerminalController {
        let controller = TerminalController()
        controller.name = nextTerminalName()
        terminals.append(controller)
        activeTerminalID = controller.id
        controller.startShell(cwd: rootURL)
        return controller
    }

    func selectTerminal(_ id: TerminalController.ID) {
        guard terminals.contains(where: { $0.id == id }) else { return }
        activeTerminalID = id
    }

    func closeTerminal(_ id: TerminalController.ID) {
        guard let index = terminals.firstIndex(where: { $0.id == id }) else { return }
        terminals.remove(at: index)
        if activeTerminalID == id {
            let fallback = min(index, terminals.count - 1)
            activeTerminalID = terminals.indices.contains(fallback) ? terminals[fallback].id : nil
        }
    }

    /// Names sessions zsh, zsh 2, zsh 3 … reusing the lowest free number so the
    /// list stays tidy after closing tabs in the middle.
    private func nextTerminalName() -> String {
        let base = (ProcessInfo.processInfo.environment["SHELL"]
            .map { URL(fileURLWithPath: $0).lastPathComponent }) ?? "zsh"
        let used = Set(terminals.map(\.name))
        if !used.contains(base) { return base }
        var n = 2
        while used.contains("\(base) \(n)") { n += 1 }
        return "\(base) \(n)"
    }
}
