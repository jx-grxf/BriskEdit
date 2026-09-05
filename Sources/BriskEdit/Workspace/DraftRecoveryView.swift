import SwiftUI

struct DraftRecoveryView: View {
    @Bindable var workspace: WorkspaceModel
    @State private var selection: RecoverableDraft.ID?
    @State private var isWorking = false

    private var selected: RecoverableDraft? {
        workspace.recoveredDrafts.first { $0.id == selection } ?? workspace.recoveredDrafts.first
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Recover Unsaved Drafts", systemImage: "clock.arrow.circlepath")
                .font(.title2.bold())
            Text("Restore a safe untitled copy, then choose where to save it. The original file is never overwritten.")
                .foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            HSplitView {
                List(workspace.recoveredDrafts, selection: $selection) { draft in
                    VStack(alignment: .leading, spacing: 3) {
                        Text(draft.displayName)
                        Text(draft.updatedAt.formatted()).font(.caption).foregroundStyle(.secondary)
                        if let path = draft.filePath {
                            Text(path).font(.caption2.monospaced()).foregroundStyle(.tertiary)
                                .lineLimit(1).truncationMode(.head)
                        }
                    }.tag(draft.id)
                }.frame(minWidth: 220).disabled(isWorking)
                ReadOnlyTextView(text: selected?.text ?? "")
                    .frame(minWidth: 400)
            }
            HStack {
                Button("Discard", role: .destructive) {
                    if let selected { run { await workspace.discardDraft(selected) } }
                }.disabled(selected == nil || isWorking)
                Spacer()
                if isWorking { ProgressView().controlSize(.small) }
                Button("Later") { workspace.showDraftRecovery = false }.disabled(isWorking)
                Button("Restore as Untitled Copy") {
                    if let selected { run { await workspace.restoreDraft(selected) } }
                }.buttonStyle(.borderedProminent).disabled(selected == nil || isWorking)
            }
        }
        .padding(20)
        .frame(minWidth: 700, minHeight: 460)
        .background(.background)
        .onAppear { selection = workspace.recoveredDrafts.first?.id }
    }

    private func run(_ operation: @escaping () async -> Void) {
        isWorking = true
        Task { await operation(); isWorking = false }
    }
}
