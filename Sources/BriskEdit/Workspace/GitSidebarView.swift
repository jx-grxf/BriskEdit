import SwiftUI

/// Which pane the workspace sidebar shows.
enum SidebarTab: Hashable {
    case files
    case sourceControl
}

extension Notification.Name {
    /// Posted after any git operation so editors can refresh their gutter diff.
    static let gitDidChange = Notification.Name("BriskEdit.gitDidChange")
}

/// Result feedback shown as a banner (push/pull/fetch/checkout).
private struct GitFeedback: Equatable {
    let text: String
    let isError: Bool
}

/// Source Control pane: branch switcher, sync (fetch / pull / push with
/// ahead·behind counts and result feedback), staged / unstaged changes with
/// stage·unstage·discard, and a commit box. Reads `git` through `GitService`.
struct GitSidebarView: View {
    @Bindable var workspace: WorkspaceModel
    let root: URL

    @State private var status: GitStatus?
    @State private var branches: [String] = []
    @State private var commitMessage = ""
    @State private var isWorking = false
    @State private var feedback: GitFeedback?
    @State private var discardTarget: GitFileChange?
    @State private var showNewBranch = false
    @State private var newBranchName = ""

    var body: some View {
        VStack(spacing: 0) {
            header
            if let feedback { feedbackBanner(feedback) }
            Divider()
            content
        }
        .task(id: workspace.reloadToken) { await reload() }
        .alert("New Branch", isPresented: $showNewBranch) {
            TextField("Branch name", text: $newBranchName)
            Button("Create") {
                let name = newBranchName.trimmingCharacters(in: .whitespaces)
                newBranchName = ""
                if !name.isEmpty { performResult("Create branch") { await GitService.createBranch(name, root: root) } }
            }
            Button("Cancel", role: .cancel) { newBranchName = "" }
        }
        .confirmationDialog(
            discardTarget.map { "Discard changes to “\($0.displayName)”?" } ?? "",
            isPresented: Binding(get: { discardTarget != nil }, set: { if !$0 { discardTarget = nil } }),
            titleVisibility: .visible
        ) {
            Button("Discard Changes", role: .destructive) {
                if let target = discardTarget { perform { await GitService.discard(target.path, root: root) } }
                discardTarget = nil
            }
            Button("Cancel", role: .cancel) { discardTarget = nil }
        } message: {
            Text("This cannot be undone.")
        }
    }

    // MARK: - Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Menu {
                    ForEach(branches, id: \.self) { branch in
                        Button {
                            if branch != status?.branch { performResult("Checkout \(branch)") { await GitService.checkout(branch, root: root) } }
                        } label: {
                            if branch == status?.branch {
                                Label(branch, systemImage: "checkmark")
                            } else {
                                Text(branch)
                            }
                        }
                    }
                    Divider()
                    Button("New Branch…") { showNewBranch = true }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "arrow.triangle.branch")
                        Text(status?.branch ?? "—").lineLimit(1).truncationMode(.middle)
                    }
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
                .disabled(status == nil)

                Spacer()
                if isWorking { ProgressView().controlSize(.small) }
                Button { Task { await reload() } } label: { Image(systemName: "arrow.clockwise") }
                    .buttonStyle(.borderless)
                    .help("Refresh status")
            }

            if status?.hasRemote == true {
                HStack(spacing: 14) {
                    if let s = status {
                        Label("\(s.behind)", systemImage: "arrow.down")
                        Label("\(s.ahead)", systemImage: "arrow.up")
                    }
                    Spacer()
                    Button { performResult("Fetch") { await GitService.fetch(root: root) } } label: { Image(systemName: "arrow.triangle.2.circlepath") }
                        .help("Fetch")
                    Button { performResult("Pull") { await GitService.pull(root: root) } } label: { Image(systemName: "arrow.down.to.line") }
                        .help("Pull (fast-forward)")
                    Button { performResult("Push") { await GitService.push(root: root) } } label: { Image(systemName: "arrow.up.to.line") }
                        .help("Push")
                }
                .font(.callout)
                .foregroundStyle(.secondary)
                .labelStyle(.titleAndIcon)
                .buttonStyle(.borderless)
                .disabled(isWorking)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    private func feedbackBanner(_ feedback: GitFeedback) -> some View {
        HStack(alignment: .top, spacing: 6) {
            Image(systemName: feedback.isError ? "exclamationmark.triangle.fill" : "checkmark.circle.fill")
                .foregroundStyle(feedback.isError ? .orange : .green)
            Text(feedback.text).font(.caption).lineLimit(5).textSelection(.enabled)
            Spacer()
            Button { self.feedback = nil } label: { Image(systemName: "xmark") }.buttonStyle(.borderless)
        }
        .padding(8)
        .background((feedback.isError ? Color.orange : Color.green).opacity(0.12))
    }

    // MARK: - Changes list

    @ViewBuilder
    private var content: some View {
        if let status, !status.isClean {
            List {
                if !status.staged.isEmpty {
                    Section("Staged Changes") {
                        ForEach(status.staged) { change in
                            row(change, action: "minus.circle", help: "Unstage") {
                                perform { await GitService.unstage(change.path, root: root) }
                            }
                        }
                    }
                }
                Section(status.staged.isEmpty ? "Changes" : "Unstaged Changes") {
                    ForEach(status.unstaged) { change in
                        row(change, action: "plus.circle", help: "Stage") {
                            perform { await GitService.stage(change.path, root: root) }
                        }
                    }
                }
            }
            .listStyle(.sidebar)
            commitBox(canCommit: !status.staged.isEmpty)
        } else {
            ContentUnavailableView {
                Label(status == nil ? "Not a Git Repository" : "No Changes", systemImage: "checkmark.seal")
            } description: {
                Text(status == nil ? "This folder isn't tracked by git." : "Your working tree is clean.")
            }
        }
    }

    private func row(_ change: GitFileChange, action: String, help: String, perform action2: @escaping () -> Void) -> some View {
        HStack(spacing: 8) {
            statusBadge(change.status)
            VStack(alignment: .leading, spacing: 1) {
                Text(change.displayName).lineLimit(1).truncationMode(.middle)
                if !change.directory.isEmpty {
                    Text(change.directory).font(.caption2).foregroundStyle(.secondary).lineLimit(1).truncationMode(.head)
                }
            }
            Spacer()
            Button(action: action2) { Image(systemName: action) }
                .buttonStyle(.borderless)
                .help(help)
        }
        .contentShape(Rectangle())
        .onTapGesture { openFile(change) }
        .contextMenu {
            Button("Open") { openFile(change) }
            if change.status != "?" {
                Button("Discard Changes…", role: .destructive) { discardTarget = change }
            }
        }
    }

    private func statusBadge(_ code: String) -> some View {
        Text(code == "?" ? "U" : code)
            .font(.system(size: 11, weight: .bold, design: .monospaced))
            .frame(width: 16)
            .foregroundStyle(color(for: code))
    }

    private func color(for code: String) -> Color {
        switch code {
        case "A": .green
        case "D": .red
        case "?": .secondary
        case "R": .blue
        default: .orange
        }
    }

    @ViewBuilder
    private func commitBox(canCommit: Bool) -> some View {
        Divider()
        VStack(spacing: 6) {
            TextField("Commit message", text: $commitMessage, axis: .vertical)
                .textFieldStyle(.roundedBorder)
                .lineLimit(1...3)
            HStack {
                Button("Stage All") { perform { await GitService.stageAll(root: root) } }
                    .controlSize(.small)
                Spacer()
                Button("Commit") {
                    let message = commitMessage
                    perform {
                        let ok = await GitService.commit(message: message, root: root)
                        if ok { await MainActor.run { commitMessage = "" } }
                        return ok
                    }
                }
                .controlSize(.small)
                .buttonStyle(.borderedProminent)
                .disabled(!canCommit || commitMessage.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(10)
    }

    // MARK: - Actions

    private func openFile(_ change: GitFileChange) {
        Task { await workspace.openFile(at: root.appendingPathComponent(change.path)) }
    }

    private func reload() async {
        async let status = GitService.status(root: root)
        async let branches = GitService.branches(root: root)
        self.status = await status
        self.branches = await branches
    }

    /// Boolean git op (stage/commit/…), then refresh + broadcast.
    private func perform(_ op: @escaping () async -> Bool) {
        isWorking = true
        Task {
            _ = await op()
            await reload()
            NotificationCenter.default.post(name: .gitDidChange, object: nil)
            isWorking = false
        }
    }

    /// Git op whose result is worth showing (push/pull/fetch/checkout). Always
    /// reports an outcome — success (green, auto-dismiss) or error (orange).
    private func performResult(_ label: String, _ op: @escaping () async -> GitResult) {
        isWorking = true
        feedback = nil
        Task {
            let result = await op()
            let text = result.output.isEmpty ? "\(label): done." : result.output
            feedback = GitFeedback(text: text, isError: !result.ok)
            await reload()
            NotificationCenter.default.post(name: .gitDidChange, object: nil)
            isWorking = false
            if result.ok {
                try? await Task.sleep(for: .seconds(5))
                if feedback?.isError == false { feedback = nil }
            }
        }
    }
}
