import Combine
import SwiftUI

struct EditorTabsView: View {
    @Bindable var workspace: WorkspaceModel
    var onOpenFile: () -> Void = {}
    @Environment(Preferences.self) private var preferences
    @SceneStorage("workspace.terminalHeight") private var storedTerminalHeight: Double = 260
    @State private var terminalResizeStart: Double?
    /// Live drag value. While the handle is dragged we update this transient
    /// state every frame and only write `SceneStorage` once on release — writing
    /// the persisted store on every frame was what made the resize lag/stutter.
    @State private var liveTerminalHeight: Double?
    @SceneStorage("workspace.previewSplitWidth") private var storedPreviewSplitWidth: Double = 400
    @State private var previewResizeStart: Double?
    @State private var livePreviewSplitWidth: Double?

    private var terminalHeight: Double { liveTerminalHeight ?? storedTerminalHeight }
    private var previewSplitWidth: Double { livePreviewSplitWidth ?? storedPreviewSplitWidth }

    var body: some View {
        editorArea
            // The open-files tab strip and the status bar are pinned as
            // safe-area *insets* rather than plain VStack siblings. On macOS 26
            // (Tahoe) a code tab's `NSTextView`/`NSScrollView`
            // (TextKit2EditorHost) gets pulled up under the nearest top bar by
            // the system's "scroll edge effect", which painted the editor over a
            // sibling tab strip and made it vanish (PDF/QuickLook hosts aren't
            // scroll views, so they never triggered it). A safe-area inset is the
            // surface that bar-under-scroll behavior is designed for: the strip
            // reserves its own space and is composited *above* any content that
            // underlaps it, so it can no longer be covered.
            .safeAreaInset(edge: .top, spacing: 0) {
                if !workspace.tabs.isEmpty {
                    VStack(spacing: 0) {
                        TabStrip(workspace: workspace)
                        Divider()
                    }
                }
            }
            .safeAreaInset(edge: .bottom, spacing: 0) {
                VStack(spacing: 0) {
                    Divider()
                    StatusBar(workspace: workspace)
                }
            }
    }

    /// The editor (or empty state) stacked above the optional terminal panel.
    /// The terminal renders regardless of whether a file is open so it can be
    /// used in a freshly opened folder.
    private var editorArea: some View {
        GeometryReader { proxy in
            VStack(spacing: 0) {
                mainSurface(width: proxy.size.width)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .layoutPriority(1)
                if workspace.shouldMountTerminalPanel {
                    let isVisible = workspace.showsTerminalPanel
                    if isVisible {
                        TerminalResizeHandle()
                            .gesture(resizeTerminalGesture(maxHeight: proxy.size.height - 180))
                    }
                    TerminalPanel(workspace: workspace)
                        .frame(height: isVisible ? clampedTerminalHeight(maxHeight: proxy.size.height - 180) : 0)
                        .opacity(isVisible ? 1 : 0)
                        .allowsHitTesting(isVisible)
                        .accessibilityHidden(!isVisible)
                        .clipped()
                        .layoutPriority(0)
                }
            }
        }
    }

    @ViewBuilder
    private func mainSurface(width: CGFloat) -> some View {
        if let tab = workspace.activeTab {
            VStack(spacing: 0) {
                if tab.document.externalChangePending {
                    ExternalChangeBanner(document: tab.document)
                }
                HStack(spacing: 0) {
                    editorSurface(for: tab)
                        .frame(minWidth: 320)
                        .layoutPriority(1)
                    if let previewKind = workspace.splitPreviewKind {
                        PreviewSplitHandle()
                            .gesture(resizePreviewGesture(maxWidth: width - 360))
                        SplitPreviewPane(kind: previewKind) { workspace.splitPreviewKind = nil }
                            .frame(width: clampedPreviewWidth(maxWidth: width - 360))
                            .layoutPriority(0)
                    }
                }
            }
        } else {
            emptyState
        }
    }

    private var emptyState: some View {
        ContentUnavailableView {
            Label("BriskEdit", systemImage: "text.cursor")
        } description: {
            Text("Open a file or drop files here.")
        } actions: {
            HStack {
                Button("New File") { workspace.newUntitled() }
                    .keyboardShortcut("n", modifiers: .command)
                Button("Open File…") { onOpenFile() }
            }
        }
    }

    private func clampedPreviewWidth(maxWidth: CGFloat) -> CGFloat {
        min(max(CGFloat(previewSplitWidth), 240), max(280, maxWidth))
    }

    private func resizePreviewGesture(maxWidth: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 1)
            .onChanged { value in
                let start = previewResizeStart ?? previewSplitWidth
                previewResizeStart = start
                let proposed = start - Double(value.translation.width)
                livePreviewSplitWidth = Double(min(max(CGFloat(proposed), 240), max(280, maxWidth)))
            }
            .onEnded { _ in
                if let live = livePreviewSplitWidth { storedPreviewSplitWidth = live }
                previewResizeStart = nil
                livePreviewSplitWidth = nil
            }
    }

    private func clampedTerminalHeight(maxHeight: CGFloat) -> CGFloat {
        min(max(CGFloat(terminalHeight), 140), max(180, maxHeight))
    }

    private func resizeTerminalGesture(maxHeight: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 1)
            .onChanged { value in
                let start = terminalResizeStart ?? terminalHeight
                terminalResizeStart = start
                let proposed = start - Double(value.translation.height)
                liveTerminalHeight = Double(min(max(CGFloat(proposed), 140), max(180, maxHeight)))
            }
            .onEnded { _ in
                if let live = liveTerminalHeight { storedTerminalHeight = live }
                terminalResizeStart = nil
                liveTerminalHeight = nil
            }
    }

    @ViewBuilder
    private func editorSurface(for tab: EditorTab) -> some View {
        if let previewKind = tab.previewKind {
            previewSurface(for: previewKind)
                .id(tab.id)
        } else if workspace.showMarkdownPreview && tab.document.language == .markdown {
            HStack(spacing: 0) {
                TextKit2EditorHost(document: tab.document, theme: preferences.editorTheme)
                    .id(tab.id)
                    .frame(minWidth: 360)
                    .layoutPriority(1)
                Divider()
                MarkdownPreview(document: tab.document)
                    .frame(width: 340)
            }
        } else {
            TextKit2EditorHost(document: tab.document, theme: preferences.editorTheme)
                .id(tab.id)
                .frame(minWidth: 360)
        }
    }

    @ViewBuilder
    private func previewSurface(for kind: PreviewKind) -> some View {
        switch kind {
        case .pdf(let url):
            PDFViewerHost(url: url)
        case .quickLook(let url):
            QuickLookPreviewHost(url: url)
        }
    }
}

/// Shown when a file changed on disk while the buffer had unsaved edits. Lets
/// the user discard their edits and load the disk version, or keep editing.
private struct ExternalChangeBanner: View {
    let document: TextDocument

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
            Text("“\(document.displayName)” changed on disk. You have unsaved edits.")
                .font(.callout)
            Spacer()
            Button("Reload from Disk") {
                Task { await document.reloadFromDisk() }
            }
            Button("Keep Mine") {
                document.externalChangePending = false
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(.orange.opacity(0.12))
        .overlay(alignment: .bottom) { Divider() }
    }
}

private struct PreviewSplitHandle: View {
    var body: some View {
        ZStack {
            Divider()
            Rectangle()
                .fill(.clear)
                .frame(width: 8)
                .overlay {
                    Capsule()
                        .fill(Color.secondary.opacity(0.35))
                        .frame(width: 3, height: 36)
                }
        }
        .frame(width: 8)
        .contentShape(Rectangle())
        .pointerStyle(.columnResize)
        .accessibilityLabel("Resize preview pane")
    }
}

private struct SplitPreviewPane: View {
    let kind: PreviewKind
    let onClose: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 6) {
                Image(systemName: kind.systemImage)
                Text(kind.url.lastPathComponent)
                    .font(.caption.weight(.semibold))
                    .lineLimit(1)
                    .truncationMode(.middle)
                Spacer()
                Button("Close", systemImage: "xmark") { onClose() }
                    .buttonStyle(.borderless)
                    .labelStyle(.iconOnly)
            }
            .padding(.horizontal, 10)
            .frame(height: 30)
            .background(.bar)
            Divider()
            previewSurface
        }
    }

    @ViewBuilder
    private var previewSurface: some View {
        switch kind {
        case .pdf(let url):
            PDFViewerHost(url: url)
        case .quickLook(let url):
            QuickLookPreviewHost(url: url)
        }
    }
}

private struct TerminalResizeHandle: View {
    var body: some View {
        VStack(spacing: 0) {
            Divider()
            Rectangle()
                .fill(.clear)
                .frame(height: 8)
                .overlay {
                    Capsule()
                        .fill(Color.secondary.opacity(0.35))
                        .frame(width: 36, height: 3)
                }
            Divider()
        }
        .contentShape(Rectangle())
        .pointerStyle(.rowResize)
        .accessibilityLabel("Resize terminal")
    }
}

private struct TabStrip: View {
    @Bindable var workspace: WorkspaceModel

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 0) {
                ForEach(workspace.tabs) { tab in
                    TabChip(
                        tab: tab,
                        isActive: tab.id == workspace.activeTabID,
                        onSelect: { workspace.selectTab(tab.id) },
                        onClose: { workspace.requestCloseTab(tab.id) }
                    )
                    Divider().frame(height: 18)
                }
            }
        }
        // Hard scroll edge so tabs are cut crisply at the strip's bounds instead
        // of the macOS 26 soft fade, which let them bleed *under* the translucent
        // sidebar when scrolled. `.clipped()` backs it up so nothing renders past
        // the leading (sidebar) edge.
        .scrollEdgeEffectStyle(.hard, for: .horizontal)
        .frame(height: 32)
        .background(.thinMaterial)
        .clipped()
    }
}

private struct TabChip: View {
    let tab: EditorTab
    let isActive: Bool
    let onSelect: () -> Void
    let onClose: () -> Void

    var body: some View {
        HStack(spacing: 6) {
            FileTypeIcon(url: tab.document.fileURL, isDirectory: false, language: tab.document.language, size: 14)
            Text(tab.document.displayName)
                .lineLimit(1)
                .truncationMode(.middle)
                .frame(minWidth: 80, idealWidth: 140, maxWidth: 220, alignment: .leading)
            if tab.document.isDirty {
                Circle().frame(width: 6, height: 6).foregroundStyle(.tint)
            }
            Button(action: onClose) {
                Image(systemName: "xmark")
                    .imageScale(.small)
            }
            .buttonStyle(.plain)
            .opacity(0.6)
        }
        .padding(.horizontal, 10)
        .frame(height: 32)
        .background(isActive ? Color.accentColor.opacity(0.18) : Color.clear)
        .contentShape(Rectangle())
        .onTapGesture(perform: onSelect)
    }
}

/// Compact error/warning counts in the status bar; hidden when the file is clean.
private struct DiagnosticSummary: View {
    let diagnostics: [Diagnostic]

    var body: some View {
        let errors = diagnostics.filter { $0.severity == .error }.count
        let warnings = diagnostics.filter { $0.severity == .warning }.count
        if errors > 0 || warnings > 0 {
            HStack(spacing: 8) {
                if errors > 0 {
                    Label("\(errors)", systemImage: "xmark.octagon.fill")
                        .foregroundStyle(.red)
                }
                if warnings > 0 {
                    Label("\(warnings)", systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                }
            }
            .font(.caption.monospaced())
            .labelStyle(.titleAndIcon)
        }
    }
}

private struct StatusBar: View {
    let workspace: WorkspaceModel

    var body: some View {
        HStack(spacing: 12) {
            if let doc = workspace.activeTab?.document {
                Text(doc.displayName).font(.caption.monospaced())
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .frame(maxWidth: 220, alignment: .leading)
                Text(encodingLabel(doc.encoding)).font(.caption.monospaced())
                    .lineLimit(1)
                Text(doc.language.rawValue).font(.caption.monospaced()).foregroundStyle(.secondary)
                    .lineLimit(1)
                Text("Ln \(doc.cursorLine), Col \(doc.cursorColumn)").font(.caption.monospaced()).foregroundStyle(.secondary)
                    .lineLimit(1)
                Text(doc.fileSizeLabel).font(.caption.monospaced()).foregroundStyle(.secondary)
                    .lineLimit(1)
                Text(doc.isDirty ? "Modified" : "Saved").font(.caption.monospaced()).foregroundStyle(.secondary)
                    .lineLimit(1)
                DiagnosticSummary(diagnostics: doc.diagnostics)
            }
            Spacer()
            GitStatusBarView(root: workspace.rootURL)
            if let doc = workspace.activeTab?.document {
                IntelliSenseStatusView(language: doc.language)
            }
        }
        .padding(.horizontal, 12)
        .frame(height: 22)
        .background(.thinMaterial)
    }

    private func encodingLabel(_ encoding: String.Encoding) -> String {
        switch encoding {
        case .utf8: "UTF-8"
        case .utf16: "UTF-16"
        case .utf16LittleEndian: "UTF-16 LE"
        case .utf16BigEndian: "UTF-16 BE"
        case .ascii: "ASCII"
        default: "Encoding \(encoding.rawValue)"
        }
    }
}

/// Branch + ahead·behind + uncommitted-change count in the status bar. Reads
/// `git` for the workspace root and refreshes itself whenever a git operation
/// broadcasts `.gitDidChange` or the window becomes key (so a save elsewhere is
/// reflected). Renders nothing outside a repository.
private struct GitStatusBarView: View {
    let root: URL?
    @State private var status: GitStatus?

    var body: some View {
        Group {
            if let status, let branch = status.branch {
                HStack(spacing: 8) {
                    Label(branch, systemImage: "arrow.triangle.branch")
                        .lineLimit(1)
                        .truncationMode(.middle)
                    if status.hasRemote && (status.ahead > 0 || status.behind > 0) {
                        HStack(spacing: 3) {
                            if status.behind > 0 { Label("\(status.behind)", systemImage: "arrow.down") }
                            if status.ahead > 0 { Label("\(status.ahead)", systemImage: "arrow.up") }
                        }
                    }
                    if !status.isClean {
                        Label("\(changedFileCount(status))", systemImage: "pencil")
                            .foregroundStyle(.orange)
                    }
                }
                .font(.caption.monospaced())
                .foregroundStyle(.secondary)
                .labelStyle(.titleAndIcon)
            }
        }
        .task(id: root) { await reload() }
        .onReceive(NotificationCenter.default.publisher(for: .gitDidChange)) { _ in
            Task { await reload() }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didBecomeKeyNotification)) { _ in
            Task { await reload() }
        }
    }

    /// Distinct files touched (a file staged *and* modified counts once).
    private func changedFileCount(_ status: GitStatus) -> Int {
        Set(status.changes.map(\.path)).count
    }

    private func reload() async {
        guard let root else { status = nil; return }
        status = await GitService.status(root: root)
    }
}

private struct IntelliSenseStatusView: View {
    let language: SourceLanguage
    @State private var status: LSPToolStatus = .unsupported
    @State private var isChecking = false

    var body: some View {
        HStack(spacing: 5) {
            Circle()
                .fill(indicatorColor)
                .frame(width: 7, height: 7)
            Text("IntelliSense: \(status.serverName)")
                .font(.caption.monospaced())
                .lineLimit(1)
        }
        .foregroundStyle(foregroundStyle)
        .help(status.detail)
        .task(id: language) {
            isChecking = true
            status = await LSPService.toolStatus(for: language)
            isChecking = false
        }
    }

    private var indicatorColor: Color {
        if isChecking { return Color.secondary }
        return switch status.state {
        case .available: Color.green
        case .missing: Color.orange
        case .unsupported: Color.secondary
        }
    }

    private var foregroundStyle: Color {
        return switch status.state {
        case .available: Color.secondary
        case .missing: Color.orange
        case .unsupported: Color.secondary
        }
    }
}
