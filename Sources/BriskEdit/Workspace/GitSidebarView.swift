import AppKit
import SwiftUI

/// Which pane the workspace sidebar shows.
enum SidebarTab: Hashable {
    case files
    case search
    case outline
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
    @State private var commits: [GitCommit] = []
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
        // The sidebar panes are kept mounted in a ZStack, so `.task` doesn't
        // re-run when the user switches *to* Source Control — reload explicitly so
        // a change made before opening the pane is already there, not only after a
        // manual refresh.
        .onChange(of: workspace.sidebarTab) { _, tab in
            if tab == .sourceControl { Task { await reload() } }
        }
        // Reflect changes made elsewhere: a git op from another component, or a
        // save/commit in another app while we were away (window re-activates).
        // Guarded to the visible pane so background windows don't scan needlessly.
        .onReceive(NotificationCenter.default.publisher(for: .gitDidChange)) { _ in
            if workspace.sidebarTab == .sourceControl { Task { await reload() } }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didBecomeKeyNotification)) { _ in
            if workspace.sidebarTab == .sourceControl { Task { await reload() } }
        }
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
        if status == nil {
            ContentUnavailableView {
                Label("Not a Git Repository", systemImage: "checkmark.seal")
            } description: {
                Text("This folder isn't tracked by git.")
            }
            // Fill the column so the header stays pinned to the top. Without an
            // explicit greedy frame the empty-state view only claims its
            // intrinsic height, the whole sidebar VStack collapses, and the
            // split view centers it — leaving a large gap above the header.
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if let status {
            VStack(spacing: 0) {
                List {
                    if status.isClean {
                        Section {
                            Label("Working tree clean", systemImage: "checkmark.seal")
                                .foregroundStyle(.secondary)
                                .font(.callout)
                        }
                    }
                    if !status.staged.isEmpty {
                        Section("Staged Changes") {
                            ForEach(status.staged) { change in
                                row(change, action: "minus.circle", help: "Unstage") {
                                    perform { await GitService.unstage(change.path, root: root) }
                                }
                            }
                        }
                    }
                    if !status.unstaged.isEmpty {
                        Section(status.staged.isEmpty ? "Changes" : "Unstaged Changes") {
                            ForEach(status.unstaged) { change in
                                row(change, action: "plus.circle", help: "Stage") {
                                    perform { await GitService.stage(change.path, root: root) }
                                }
                            }
                        }
                    }
                    if !commits.isEmpty {
                        Section(commitsSectionTitle) {
                            ForEach(commits) { commit in commitRow(commit) }
                        }
                    }
                }
                .listStyle(.sidebar)
                if !status.isClean {
                    commitBox(canCommit: !status.staged.isEmpty)
                }
            }
        }
    }

    private var commitsSectionTitle: String {
        let unpushed = commits.filter(\.isUnpushed).count
        return unpushed > 0 ? "Commits · \(unpushed) unpushed" : "Commits"
    }

    /// A commit in the history list: a graph lane (accent dot = not yet pushed),
    /// the subject, short hash, relative time and author.
    private func commitRow(_ commit: GitCommit) -> some View {
        HStack(alignment: .top, spacing: 9) {
            // Single-lane graph: a full-height hairline so consecutive rows read
            // as one timeline, with a dot marking this commit.
            ZStack {
                Rectangle()
                    .fill(Color.secondary.opacity(0.25))
                    .frame(width: 1.5)
                Circle()
                    .fill(commit.isUnpushed ? Color.accentColor : Color.secondary)
                    .frame(width: 9, height: 9)
                    .overlay(Circle().stroke(Color(nsColor: .controlBackgroundColor), lineWidth: 2))
            }
            .frame(width: 14)
            .frame(maxHeight: .infinity)
            VStack(alignment: .leading, spacing: 2) {
                Text(commit.subject)
                    .font(.callout)
                    .lineLimit(1)
                    .truncationMode(.tail)
                HStack(spacing: 6) {
                    Text(commit.shortHash)
                        .font(.caption2.monospaced())
                        .foregroundStyle(commit.isUnpushed ? AnyShapeStyle(.tint) : AnyShapeStyle(.secondary))
                    Text("·").foregroundStyle(.tertiary)
                    Text(commit.relativeDate).foregroundStyle(.secondary)
                    Text("·").foregroundStyle(.tertiary)
                    Text(commit.author).foregroundStyle(.secondary).lineLimit(1).truncationMode(.tail)
                }
                .font(.caption2)
            }
            Spacer(minLength: 0)
            if commit.isUnpushed {
                Image(systemName: "arrow.up.circle")
                    .font(.caption)
                    .foregroundStyle(.tint)
                    .help("Not pushed yet")
            }
        }
        .padding(.vertical, 2)
        .contextMenu {
            Button("Copy Commit SHA") { copy(commit.hash) }
            Button("Copy Message") { copy(commit.subject) }
        }
    }

    private func copy(_ string: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(string, forType: .string)
    }

    private func row(_ change: GitFileChange, action: String, help: String, perform action2: @escaping () -> Void) -> some View {
        HStack(spacing: 8) {
            Button {
                openFile(change)
            } label: {
                HStack(spacing: 8) {
                    statusBadge(change.status)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(change.displayName).lineLimit(1).truncationMode(.middle)
                        if !change.directory.isEmpty {
                            Text(change.directory).font(.caption2).foregroundStyle(.secondary).lineLimit(1).truncationMode(.head)
                        }
                    }
                }
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Open \(change.displayName)")
            Spacer()
            Button(action: action2) { Image(systemName: action) }
                .buttonStyle(.borderless)
                .help(help)
                .accessibilityLabel("\(help) \(change.displayName)")
        }
        .contentShape(Rectangle())
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
        async let commits = GitService.recentCommits(root: root)
        self.status = await status
        self.branches = await branches
        self.commits = await commits
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
