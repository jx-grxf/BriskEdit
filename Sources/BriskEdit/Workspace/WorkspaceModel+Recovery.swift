import Foundation

extension WorkspaceModel {
    func loadRecoverableDrafts() async {
        do {
            recoveredDrafts = try await DraftRecoveryStore.shared.recoverableDrafts()
            let warnings = await DraftRecoveryStore.shared.takeWarnings()
            if !warnings.isEmpty { lastError = warnings.joined(separator: "\n") }
            showDraftRecovery = !recoveredDrafts.isEmpty
        } catch {
            lastError = "Could not load recovery drafts: \(error.localizedDescription)"
        }
    }

    func restoreDraft(_ draft: RecoverableDraft) async {
        // Restore as an untitled copy. This cannot race or overwrite an already
        // open buffer for the original path; the user chooses a destination via Save As.
        let document = TextDocument.recovered(draft)
        do { try await document.persistRecoverySnapshotNow(minimumGeneration: draft.generation + 1) }
        catch { lastError = "Could not adopt recovered draft: \(error.localizedDescription)"; return }
        let tab = EditorTab(document: document)
        tabs.append(tab)
        activeTabID = tab.id
        recoveredDrafts.removeAll { $0.id == draft.id }
        showDraftRecovery = !recoveredDrafts.isEmpty
    }

    func discardDraft(_ draft: RecoverableDraft) async {
        do { try await DraftRecoveryStore.shared.remove(id: draft.id, generation: draft.generation + 1) }
        catch { lastError = "Could not discard draft: \(error.localizedDescription)"; return }
        recoveredDrafts.removeAll { $0.id == draft.id }
        showDraftRecovery = !recoveredDrafts.isEmpty
    }
}
