import AppKit
import Foundation

// File-tree CRUD: create / delete / duplicate / rename / move / drop, plus the
// small async FileManager wrappers and prompt helpers they rely on.
extension WorkspaceModel {
    /// Folder a new file/folder lands in: the selected directory, the parent of
    /// the selected file, or — when nothing is selected (e.g. the user clicked
    /// the empty area of the file tree) — the workspace root.
    var currentDirectory: URL? {
        if let selected = selectedSidebarURL {
            let isDirectory = (try? selected.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true
            return isDirectory ? selected : selected.deletingLastPathComponent()
        }
        return rootURL
    }

    func promptNewFile(in directory: URL? = nil) {
        guard let dir = directory ?? currentDirectory else { return }
        guard let name = promptForName(title: "New File", message: "Create a file in “\(dir.lastPathComponent)”", placeholder: "untitled.c", defaultValue: "") else { return }
        let url = dir.appendingPathComponent(name)
        guard !FileManager.default.fileExists(atPath: url.path) else {
            lastError = "“\(name)” already exists."
            return
        }
        Task { [weak self] in
            guard let self else { return }
            do {
                try await writeEmptyFile(at: url)
                expandedDirectories.insert(dir)
                refreshDirectory(dir)
                selectedSidebarURL = url
                await openFile(at: url)
            } catch {
                lastError = "Could not create \(name): \(error.localizedDescription)"
            }
        }
    }

    func promptNewFolder(in directory: URL? = nil) {
        guard let dir = directory ?? currentDirectory else { return }
        guard let name = promptForName(title: "New Folder", message: "Create a folder in “\(dir.lastPathComponent)”", placeholder: "untitled folder", defaultValue: "") else { return }
        let url = dir.appendingPathComponent(name, isDirectory: true)
        guard !FileManager.default.fileExists(atPath: url.path) else {
            lastError = "“\(name)” already exists."
            return
        }
        Task { [weak self] in
            guard let self else { return }
            do {
                try await createDirectory(at: url)
                expandedDirectories.insert(dir)
                expandedDirectories.insert(url)
                refreshFileTree()
                selectedSidebarURL = url
            } catch {
                lastError = "Could not create \(name): \(error.localizedDescription)"
            }
        }
    }

    func deleteFile(_ url: URL) {
        let alert = NSAlert()
        alert.messageText = "Move “\(url.lastPathComponent)” to Trash?"
        alert.informativeText = "You can restore it from the Trash."
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Move to Trash")
        alert.addButton(withTitle: "Cancel")
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        Task { [weak self] in
            guard let self else { return }
            do {
                guard await resolveDirtyTabsBeforeTrash(url) else { return }
                try await trashItem(at: url)
                closeTabsAcrossWindows(referencing: url)
                refreshDirectory(url.deletingLastPathComponent())
            } catch {
                lastError = "Could not delete \(url.lastPathComponent): \(error.localizedDescription)"
            }
        }
    }

    func duplicateFile(_ url: URL) {
        let fm = FileManager.default
        let ext = url.pathExtension
        let base = url.deletingPathExtension().lastPathComponent
        let dir = url.deletingLastPathComponent()
        var candidate = dir.appendingPathComponent(ext.isEmpty ? "\(base) copy" : "\(base) copy.\(ext)")
        var index = 2
        while fm.fileExists(atPath: candidate.path) {
            candidate = dir.appendingPathComponent(ext.isEmpty ? "\(base) copy \(index)" : "\(base) copy \(index).\(ext)")
            index += 1
        }
        Task { [weak self] in
            guard let self else { return }
            do {
                try await copyItem(at: url, to: candidate)
                refreshDirectory(candidate.deletingLastPathComponent())
            } catch {
                lastError = "Could not duplicate \(url.lastPathComponent): \(error.localizedDescription)"
            }
        }
    }

    func renameFile(_ url: URL) {
        guard let name = promptForName(title: "Rename", message: "Rename “\(url.lastPathComponent)”", placeholder: "", defaultValue: url.lastPathComponent), name != url.lastPathComponent else { return }
        let destination = url.deletingLastPathComponent().appendingPathComponent(name)
        guard !FileManager.default.fileExists(atPath: destination.path) else {
            lastError = "“\(name)” already exists."
            return
        }
        Task { [weak self] in
            guard let self else { return }
            do {
                let relocations = try await prepareTabRelocations(from: url, to: destination)
                do {
                    try await moveItem(at: url, to: destination)
                    finishTabRelocations(relocations)
                } catch {
                    cancelTabRelocations(relocations)
                    throw error
                }
                persistSession()
                refreshDirectory(destination.deletingLastPathComponent())
                selectedSidebarURL = destination
            } catch {
                lastError = "Could not rename \(url.lastPathComponent): \(error.localizedDescription)"
            }
        }
    }

    /// Handles a drop onto a folder in the tree: files already inside the
    /// workspace are moved, files coming from outside (Finder, Downloads, …) are
    /// copied in.
    @discardableResult
    func handleTreeDrop(_ urls: [URL], into directory: URL) -> Bool {
        let root = rootURL?.standardizedFileURL.path
        var changed = false
        for url in urls {
            let inside = root.map { url.standardizedFileURL.path.hasPrefix($0 + "/") } ?? false
            if inside {
                if moveFile(url, into: directory) { changed = true }
            } else {
                importExternalFile(url, into: directory)
                changed = true
            }
        }
        return changed
    }

    /// Copies an external file/folder into `directory`, disambiguating the name.
    func importExternalFile(_ source: URL, into directory: URL) {
        let fm = FileManager.default
        var destination = directory.appendingPathComponent(source.lastPathComponent)
        if fm.fileExists(atPath: destination.path) {
            let base = source.deletingPathExtension().lastPathComponent
            let ext = source.pathExtension
            var index = 2
            repeat {
                destination = directory.appendingPathComponent(ext.isEmpty ? "\(base) \(index)" : "\(base) \(index).\(ext)")
                index += 1
            } while fm.fileExists(atPath: destination.path)
        }
        Task { [weak self] in
            guard let self else { return }
            do {
                try await copyItem(at: source, to: destination)
                expandedDirectories.insert(directory)
                refreshDirectory(directory)
            } catch {
                lastError = "Could not import \(source.lastPathComponent): \(error.localizedDescription)"
            }
        }
    }

    /// Handles files dropped onto the editor/workspace area: directories become
    /// the workspace root, files are opened in tabs.
    func openDropped(_ urls: [URL]) {
        for url in urls {
            let isDirectory = (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true
            if isDirectory {
                setWorkspaceRoot(url)
            } else {
                Task { await openFile(at: url) }
            }
        }
    }

    /// Moves a file/folder into `directory` (drag & drop in the file tree).
    @discardableResult
    func moveFile(_ source: URL, into directory: URL) -> Bool {
        let src = source.standardizedFileURL
        let dir = directory.standardizedFileURL
        // No-op when dropped onto its own folder, and never move a folder into
        // itself or one of its descendants.
        guard src.deletingLastPathComponent() != dir else { return false }
        guard dir != src, !dir.path.hasPrefix(src.path + "/") else { return false }

        let destination = dir.appendingPathComponent(src.lastPathComponent)
        guard !FileManager.default.fileExists(atPath: destination.path) else {
            lastError = "“\(src.lastPathComponent)” already exists in \(dir.lastPathComponent)."
            return false
        }
        Task { [weak self] in
            guard let self else { return }
            do {
                let relocations = try await prepareTabRelocations(from: src, to: destination)
                do {
                    try await moveItem(at: src, to: destination)
                    finishTabRelocations(relocations)
                } catch {
                    cancelTabRelocations(relocations)
                    throw error
                }
                persistSession()
                // Surface the moved item: open the target folder so the drop
                // result is immediately visible (matches `importExternalFile`).
                expandedDirectories.insert(dir)
                refreshDirectory(src.deletingLastPathComponent())
                refreshDirectory(dir)
            } catch {
                lastError = "Could not move \(src.lastPathComponent): \(error.localizedDescription)"
            }
        }
        return true
    }

    func revealInFinder(_ url: URL) {
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    func copyToPasteboard(_ string: String) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(string, forType: .string)
    }

    func relativePath(of url: URL) -> String {
        guard let root = rootURL else { return url.path }
        if url.path.hasPrefix(root.path) {
            let trimmed = url.path.dropFirst(root.path.count)
            return trimmed.hasPrefix("/") ? String(trimmed.dropFirst()) : String(trimmed)
        }
        return url.path
    }

    private func promptForName(title: String, message: String, placeholder: String, defaultValue: String) -> String? {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 260, height: 24))
        field.placeholderString = placeholder
        field.stringValue = defaultValue
        alert.accessoryView = field
        alert.addButton(withTitle: "OK")
        alert.addButton(withTitle: "Cancel")
        alert.window.initialFirstResponder = field
        guard alert.runModal() == .alertFirstButtonReturn else { return nil }
        let trimmed = field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private func affectedTabs(referencing url: URL) -> [(WorkspaceModel, EditorTab)] {
        let removedPath = url.standardizedFileURL.path
        return WorkspaceRegistry.models.flatMap { workspace in
            workspace.tabs.compactMap { tab in
                guard let path = tab.document.fileURL?.standardizedFileURL.path,
                      path == removedPath || path.hasPrefix(removedPath + "/") else { return nil }
                return (workspace, tab)
            }
        }
    }

    private func resolveDirtyTabsBeforeTrash(_ url: URL) async -> Bool {
        var resolvedPaths = Set<String>()
        for (workspace, tab) in affectedTabs(referencing: url) where tab.document.isDirty {
            let path = tab.document.fileURL?.standardizedFileURL.path ?? ""
            let alert = NSAlert()
            let requiresCopy = !resolvedPaths.insert(path).inserted
            alert.messageText = requiresCopy
                ? "Save this other edited copy of “\(tab.document.displayName)”?"
                : "Save changes to “\(tab.document.displayName)” before moving it to Trash?"
            alert.informativeText = "Cancel keeps the file and all open tabs unchanged."
            alert.addButton(withTitle: requiresCopy ? "Save Copy…" : "Save")
            alert.addButton(withTitle: "Don't Save")
            alert.addButton(withTitle: "Cancel")
            switch alert.runModal() {
            case .alertFirstButtonReturn:
                if requiresCopy {
                    let panel = NSSavePanel()
                    panel.nameFieldStringValue = tab.document.displayName
                    guard panel.runModal() == .OK, let destination = panel.url else { return false }
                    do {
                        try await tab.document.save(to: destination)
                        workspace.startWatching(tab)
                        workspace.persistSession()
                    } catch {
                        workspace.lastError = "Could not save copy: \(error.localizedDescription)"
                        return false
                    }
                } else if await workspace.save(tab) == false { return false }
            case .alertSecondButtonReturn:
                tab.document.discardRecoverySnapshot()
            default:
                return false
            }
        }
        return true
    }

    private func closeTabsAcrossWindows(referencing url: URL) {
        for (workspace, tab) in affectedTabs(referencing: url) { workspace.closeTab(tab.id) }
    }

    /// Re-points every open tab at the moved item — including, when a *folder*
    /// was renamed/moved, all tabs on files inside it — and restarts their
    /// watchers so external changes keep being picked up.
    private struct TabRelocation {
        let workspace: WorkspaceModel
        let tab: EditorTab
        let target: URL
    }

    private func prepareTabRelocations(from oldURL: URL, to newURL: URL) async throws -> [TabRelocation] {
        let oldPath = oldURL.standardizedFileURL.path
        let newPath = newURL.standardizedFileURL.path
        var prepared: [TabRelocation] = []
        do {
            for workspace in WorkspaceRegistry.models {
                for tab in workspace.tabs {
                    guard let path = tab.document.fileURL?.standardizedFileURL.path,
                          path == oldPath || path.hasPrefix(oldPath + "/") else { continue }
                    let target = path == oldPath ? newURL : URL(fileURLWithPath: newPath + String(path.dropFirst(oldPath.count)))
                    try await tab.document.beginRelocation()
                    prepared.append(TabRelocation(workspace: workspace, tab: tab, target: target))
                }
            }
            return prepared
        } catch {
            cancelTabRelocations(prepared)
            throw error
        }
    }

    private func finishTabRelocations(_ relocations: [TabRelocation]) {
        for relocation in relocations {
            relocation.workspace.releaseLSP(relocation.tab)
            relocation.tab.document.finishRelocation(to: relocation.target)
            relocation.workspace.startWatching(relocation.tab)
            relocation.workspace.persistSession()
        }
    }

    private func cancelTabRelocations(_ relocations: [TabRelocation]) {
        for relocation in relocations { relocation.tab.document.cancelRelocation() }
    }

    private func writeEmptyFile(at url: URL) async throws {
        try await Task.detached(priority: .userInitiated) {
            try Data().write(to: url)
        }.value
    }

    private func createDirectory(at url: URL) async throws {
        try await Task.detached(priority: .userInitiated) {
            try FileManager.default.createDirectory(at: url, withIntermediateDirectories: false)
        }.value
    }

    private func trashItem(at url: URL) async throws {
        try await Task.detached(priority: .userInitiated) {
            try FileManager.default.trashItem(at: url, resultingItemURL: nil)
        }.value
    }

    private func copyItem(at source: URL, to destination: URL) async throws {
        try await Task.detached(priority: .userInitiated) {
            try FileManager.default.copyItem(at: source, to: destination)
        }.value
    }

    private func moveItem(at source: URL, to destination: URL) async throws {
        try await Task.detached(priority: .userInitiated) {
            try FileManager.default.moveItem(at: source, to: destination)
        }.value
    }
}
