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
    var showTerminal: Bool = true
    var showMarkdownPreview: Bool = true
    var showHiddenFiles: Bool = false
    var reloadToken = UUID()
    var selectedSidebarURL: URL?
    var lastError: String?
    let terminal = TerminalController()
    private var childCache: [FileTreeCacheKey: [FileNode]] = [:]

    init() {
        if let path = UserDefaults.standard.string(forKey: Keys.lastWorkspaceRoot) {
            let url = URL(fileURLWithPath: path)
            if FileManager.default.fileExists(atPath: url.path) {
                rootURL = url
            }
        }
    }

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
            if tabs.count == 1,
               let current = tabs.first,
               current.document.fileURL == nil,
               current.document.text.isEmpty,
               !current.document.isDirty {
                tabs = [tab]
            } else {
                tabs.append(tab)
            }
            activeTabID = tab.id
        } catch {
            NSLog("BriskEdit: failed to load %@: %@", url.path, String(describing: error))
            lastError = "Could not open \(url.lastPathComponent): \(error.localizedDescription)"
        }
    }

    func ensureInitialDocument() {
        if tabs.isEmpty {
            newUntitled()
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
        selectedSidebarURL = tabs.first { $0.id == id }?.document.fileURL
    }

    func setWorkspaceRoot(_ url: URL) {
        rootURL = url
        selectedSidebarURL = nil
        childCache.removeAll(keepingCapacity: true)
        reloadToken = UUID()
        UserDefaults.standard.set(url.path, forKey: Keys.lastWorkspaceRoot)
    }

    func refreshFileTree() {
        childCache.removeAll(keepingCapacity: true)
        reloadToken = UUID()
    }

    func toggleHiddenFiles() {
        showHiddenFiles.toggle()
        childCache.removeAll(keepingCapacity: true)
        reloadToken = UUID()
    }

    func loadChildren(of url: URL) async -> [FileNode] {
        let key = FileTreeCacheKey(url: url, includeHidden: showHiddenFiles)
        if let cached = childCache[key] {
            return cached
        }
        let includeHidden = showHiddenFiles
        let loaded = await Task.detached(priority: .userInitiated) {
            FileNode.children(of: url, includeHidden: includeHidden)
        }.value
        childCache[key] = loaded
        return loaded
    }

    func runActiveDocument() {
        showTerminal = true
        terminal.runActiveDocument(activeTab?.document, workspaceRoot: rootURL)
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
            lastError = "Could not save \(tab.document.displayName): \(error.localizedDescription)"
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
            lastError = "Could not save \(tab.document.displayName): \(error.localizedDescription)"
        }
    }

    private enum Keys {
        static let lastWorkspaceRoot = "workspace.lastRoot"
    }

    private struct FileTreeCacheKey: Hashable {
        let url: URL
        let includeHidden: Bool
    }
}
