import AppKit
import Foundation

// Running the active document and the diagnostics check that follows.
extension WorkspaceModel {
    /// Runs a syntax/type check on the active document and stores the findings
    /// for the gutter. No-op for languages without a check driver.
    func checkActiveDocument() async {
        guard let doc = activeTab?.document else { return }
        doc.diagnostics = await DiagnosticsService.check(text: doc.text, language: doc.language, fileURL: doc.fileURL) ?? []
    }

    func runActiveDocument() {
        showTerminal = true
        Task { [weak self] in
            guard let self else { return }
            guard await self.saveBeforeProjectRunIfNeeded() else { return }
            guard await self.installMissingRunToolsIfNeeded() else { return }
            await self.ensureTerminal().runActiveDocument(self.activeTab?.document, workspaceRoot: self.rootURL)
            await self.checkActiveDocument()
        }
    }

    private func saveBeforeProjectRunIfNeeded() async -> Bool {
        guard let tab = activeTab,
              RunService.requiresSaveBeforeRun(document: tab.document, workspaceRoot: rootURL) else {
            return true
        }
        let alert = NSAlert()
        alert.messageText = "Save “\(tab.document.displayName)” before running?"
        alert.informativeText = "Project runs use files on disk. Unsaved edits would be ignored."
        alert.addButton(withTitle: "Save and Run")
        alert.addButton(withTitle: "Cancel")
        guard alert.runModal() == .alertFirstButtonReturn else { return false }
        return await save(tab)
    }

    private func installMissingRunToolsIfNeeded() async -> Bool {
        guard let doc = activeTab?.document else { return true }
        let language = doc.language
        let missingGroups = await ToolHealthService.missingRunRequirements(for: language, workspaceRoot: rootURL)
        guard let firstGroup = missingGroups.first, let descriptor = firstGroup.first else { return true }

        let names = firstGroup.map(\.name).joined(separator: " or ")
        let alert = NSAlert()
        alert.messageText = "\(names) is required to run \(language.rawValue) files."
        alert.informativeText = "BriskEdit can try to install it now, or you can install it yourself and run again."
        alert.addButton(withTitle: "Install")
        alert.addButton(withTitle: "Cancel")
        alert.addButton(withTitle: "Open Tool Health")
        let response = alert.runModal()
        if response == .alertThirdButtonReturn {
            showToolHealth = true
            return false
        }
        guard response == .alertFirstButtonReturn else { return false }
        let result = await ToolHealthService.install(descriptor)
        if !result.ok {
            lastError = result.output
            showToolHealth = true
            return false
        }
        return (await ToolHealthService.missingRunRequirements(for: language, workspaceRoot: rootURL)).isEmpty
    }
}
