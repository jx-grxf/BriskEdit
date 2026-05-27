import AppKit
import Foundation
import Observation

@MainActor
@Observable
final class WorkspaceModel {
    var rootURL: URL?
    var tabs: [EditorTab] = []
    var activeTabID: EditorTab.ID?
    var showCommandPalette: Bool = false
    var selectedSidebarURL: URL?

    var activeTab: EditorTab? {
        guard let id = activeTabID else { return nil }
        return tabs.first { $0.id == id }
    }

    func openFile(at url: URL) async {
        if let existing = tabs.first(where: { $0.document.fileURL == url }) {
            activeTabID = existing.id
            return
        }
        do {
            let doc = try await TextDocument.load(from: url)
            let tab = EditorTab(document: doc)
            tabs.append(tab)
            activeTabID = tab.id
        } catch {
            NSLog("BriskEdit: failed to load %@: %@", url.path, String(describing: error))
        }
    }

    func newUntitled() {
        let doc = TextDocument.empty()
        let tab = EditorTab(document: doc)
        tabs.append(tab)
        activeTabID = tab.id
    }

    func closeTab(_ id: EditorTab.ID) {
        guard let index = tabs.firstIndex(where: { $0.id == id }) else { return }
        tabs.remove(at: index)
        if activeTabID == id {
            let fallback = tabs.indices.contains(index) ? tabs[index] : tabs.last
            activeTabID = fallback?.id
        }
    }

    func selectTab(_ id: EditorTab.ID) {
        activeTabID = id
    }

    func setWorkspaceRoot(_ url: URL) {
        rootURL = url
    }

    func saveActiveTab() async {
        guard let tab = activeTab else { return }
        if tab.document.fileURL == nil {
            await saveActiveTabAs()
            return
        }
        do {
            try await tab.document.save()
        } catch {
            NSLog("BriskEdit: save failed: %@", String(describing: error))
        }
    }

    func saveActiveTabAs() async {
        guard let tab = activeTab else { return }
        let panel = NSSavePanel()
        panel.nameFieldStringValue = tab.document.displayName
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try await tab.document.save(to: url)
        } catch {
            NSLog("BriskEdit: save-as failed: %@", String(describing: error))
        }
    }
}
