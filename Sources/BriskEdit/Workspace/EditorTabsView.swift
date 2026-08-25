import AppKit
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
    @SceneStorage("workspace.markdownPreviewWidth") private var storedMarkdownPreviewWidth: Double = 380
    @State private var markdownResizeStart: Double?
    @State private var liveMarkdownPreviewWidth: Double?

    private var terminalHeight: Double { liveTerminalHeight ?? storedTerminalHeight }
    private var previewSplitWidth: Double { livePreviewSplitWidth ?? storedPreviewSplitWidth }
    private var markdownPreviewWidth: Double { liveMarkdownPreviewWidth ?? storedMarkdownPreviewWidth }

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
                        if let active = workspace.activeTab, active.special == nil {
                            BreadcrumbBar(workspace: workspace)
                            Divider()
                        }
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
                    // Keep the terminal at a stable nonzero height even while
                    // hidden: collapsing its frame would resize the live PTY
                    // (SIGWINCH) and wreck running TUI sessions. The inner fixed
                    // frame pins SwiftTerm's size; only the layout slot collapses.
                    TerminalPanel(workspace: workspace)
                        .frame(height: clampedTerminalHeight(maxHeight: proxy.size.height - 180))
                        .frame(height: isVisible ? clampedTerminalHeight(maxHeight: proxy.size.height - 180) : 0, alignment: .top)
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
                    editorSurface(for: tab, availableWidth: width)
                        .frame(minWidth: 320)
                        .layoutPriority(1)
                    if let splitContent = workspace.splitPreviewContent {
                        PreviewSplitHandle()
                            .gesture(resizePreviewGesture(maxWidth: width - 360))
                        SplitPreviewPane(
                            content: splitContent,
                            markdownDocument: markdownDocument(for: splitContent),
                            onClose: { workspace.splitPreviewContent = nil },
                            onOpenFile: { url in Task { await workspace.openFile(at: url) } }
                        )
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
        WelcomeView(
            recents: RecentWorkspacesStore.shared.folders,
            onNewFile: { workspace.newUntitled() },
            onOpenFile: onOpenFile,
            onOpenFolder: openFolderPanel,
            onOpenRecent: { url in workspace.setWorkspaceRoot(url) }
        )
    }

    @MainActor
    private func openFolderPanel() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        guard panel.runModal() == .OK, let url = panel.url else { return }
        workspace.setWorkspaceRoot(url)
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

    private func clampedMarkdownWidth(maxWidth: CGFloat) -> CGFloat {
        min(max(CGFloat(markdownPreviewWidth), 260), max(300, maxWidth))
    }

    private func resizeMarkdownGesture(maxWidth: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 1)
            .onChanged { value in
                let start = markdownResizeStart ?? markdownPreviewWidth
                markdownResizeStart = start
                let proposed = start - Double(value.translation.width)
                liveMarkdownPreviewWidth = Double(min(max(CGFloat(proposed), 260), max(300, maxWidth)))
            }
            .onEnded { _ in
                if let live = liveMarkdownPreviewWidth { storedMarkdownPreviewWidth = live }
                markdownResizeStart = nil
                liveMarkdownPreviewWidth = nil
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
    private func editorSurface(for tab: EditorTab, availableWidth: CGFloat) -> some View {
        if case .whatsNew(let version) = tab.special {
            WhatsNewView(version: version)
                .id(tab.id)
        } else if let previewKind = tab.previewKind {
            previewSurface(for: previewKind)
                .id(tab.id)
        } else if workspace.splitPreviewContent == nil,
                  workspace.showMarkdownPreview,
                  tab.document.language == .markdown,
                  availableWidth >= 760 {
            HStack(spacing: 0) {
                TextKit2EditorHost(document: tab.document, theme: preferences.editorTheme, showMinimap: preferences.effectiveShowMinimap, showHoverTooltips: preferences.effectiveShowHoverTooltips, highlightDebounce: preferences.highlightDebounce, gitDiffDebounce: preferences.gitDiffDebounce, showInlineGitBlame: preferences.effectiveShowInlineGitBlame, workspaceRootURL: workspace.rootURL, onOpenLocation: { url, line, column in
                    Task { await workspace.openFile(at: url, line: line, column: column) }
                })
                    .id(tab.id)
                    .frame(minWidth: 360)
                    .layoutPriority(1)
                PreviewSplitHandle()
                    .gesture(resizeMarkdownGesture(maxWidth: availableWidth - 360))
                MarkdownPreview(
                    document: tab.document,
                    renderDebounceMilliseconds: preferences.markdownPreviewDebounceMilliseconds,
                    onClose: { workspace.showMarkdownPreview = false },
                    onOpenFile: { url in Task { await workspace.openFile(at: url) } }
                )
                .frame(width: clampedMarkdownWidth(maxWidth: availableWidth - 360))
                .layoutPriority(0)
            }
        } else {
            TextKit2EditorHost(document: tab.document, theme: preferences.editorTheme, showMinimap: preferences.effectiveShowMinimap, showHoverTooltips: preferences.effectiveShowHoverTooltips, highlightDebounce: preferences.highlightDebounce, gitDiffDebounce: preferences.gitDiffDebounce, showInlineGitBlame: preferences.effectiveShowInlineGitBlame, workspaceRootURL: workspace.rootURL, onOpenLocation: { url, line, column in
                    Task { await workspace.openFile(at: url, line: line, column: column) }
                })
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
        case .image(let url):
            ImageViewerHost(url: url)
        }
    }

    private func markdownDocument(for content: SplitPreviewContent) -> TextDocument? {
        guard case .markdown(let id) = content else { return nil }
        return workspace.tabs.first(where: { $0.id == id })?.document
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
    let content: SplitPreviewContent
    let markdownDocument: TextDocument?
    let onClose: () -> Void
    let onOpenFile: (URL) -> Void
    @Environment(Preferences.self) private var preferences

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 6) {
                Image(systemName: systemImage)
                Text(displayName)
                    .font(.caption.weight(.semibold))
                    .lineLimit(1)
                    .truncationMode(.middle)
                Spacer()
                Button("Close", systemImage: "xmark") { onClose() }
                    .buttonStyle(.borderless)
                    .labelStyle(.iconOnly)
                    .help("Close preview")
                    .accessibilityLabel("Close preview")
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
        switch content {
        case .native(let kind):
            switch kind {
            case .pdf(let url):
                PDFViewerHost(url: url)
            case .quickLook(let url):
                QuickLookPreviewHost(url: url)
            case .image(let url):
                ImageViewerHost(url: url)
            }
        case .markdown:
            if let markdownDocument {
                MarkdownPreview(
                    document: markdownDocument,
                    showsHeader: false,
                    renderDebounceMilliseconds: preferences.markdownPreviewDebounceMilliseconds,
                    onClose: onClose,
                    onOpenFile: onOpenFile
                )
            } else {
                ContentUnavailableView("Preview Unavailable", systemImage: "doc.richtext")
            }
        }
    }

    private var displayName: String {
        switch content {
        case .native(let kind): kind.url.lastPathComponent
        case .markdown: markdownDocument?.displayName ?? "Markdown"
        }
    }

    private var systemImage: String {
        switch content {
        case .native(let kind): kind.systemImage
        case .markdown: "doc.richtext"
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

private struct TabStripWidthKey: PreferenceKey {
    static var defaultValue: CGFloat { 0 }
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = max(value, nextValue()) }
}

private struct TabContentWidthKey: PreferenceKey {
    static var defaultValue: CGFloat { 0 }
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = max(value, nextValue()) }
}

private struct TabStrip: View {
    @Bindable var workspace: WorkspaceModel
    @State private var contentWidth: CGFloat = 0
    @State private var viewportWidth: CGFloat = 0

    /// The tabs don't fit the visible strip, so offer the overflow menu. The
    /// menu's own width keeps this stable near the boundary (showing it shrinks
    /// the viewport, which keeps the condition true).
    private var isOverflowing: Bool { contentWidth > viewportWidth + 1 }

    var body: some View {
        HStack(spacing: 0) {
            ScrollViewReader { proxy in
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 0) {
                        ForEach(workspace.tabs) { tab in
                            TabChip(
                                tab: tab,
                                isActive: tab.id == workspace.activeTabID,
                                onSelect: { workspace.selectTab(tab.id) },
                                onClose: { workspace.requestCloseTab(tab.id) },
                                onCloseOthers: { workspace.requestCloseOtherTabs(keeping: tab.id) },
                                onCloseRight: { workspace.requestCloseTabsToRight(of: tab.id) },
                                onCloseAll: { workspace.requestCloseAllTabs() },
                                onOpenSplitPreview: {
                                    if let url = tab.document.fileURL {
                                        Task { await workspace.openInSplitScreen(url) }
                                    }
                                },
                                makeTransfer: { makeTabTransfer(tabID: tab.id, source: workspace) },
                                onReorder: { draggedID in reorder(draggedID, toPositionOf: tab.id) }
                            )
                            .id(tab.id)
                            Divider().frame(height: 18)
                        }
                    }
                    // Glide tabs into their new slot on reorder instead of snapping.
                    // Keyed on the id-order so it only fires when the sequence changes.
                    .animation(.spring(response: 0.3, dampingFraction: 0.82), value: workspace.tabs.map(\.id))
                    .background(GeometryReader { geo in
                        Color.clear.preference(key: TabContentWidthKey.self, value: geo.size.width)
                    })
                }
                // Hard scroll edge so tabs are cut crisply at the strip's bounds
                // instead of the macOS 26 soft fade, which let them bleed *under*
                // the translucent sidebar when scrolled.
                .scrollEdgeEffectStyle(.hard, for: .horizontal)
                .background(GeometryReader { geo in
                    Color.clear.preference(key: TabStripWidthKey.self, value: geo.size.width)
                })
                // Keep the active tab visible when it's selected from the keyboard,
                // the overflow menu, or moved with ⌃⌘←/→.
                .onChange(of: workspace.activeTabID) { _, id in
                    guard let id else { return }
                    withAnimation(.easeOut(duration: 0.2)) { proxy.scrollTo(id, anchor: .center) }
                }
            }

            if isOverflowing {
                TabOverflowMenu(workspace: workspace)
                    .transition(.opacity)
            }
        }
        .frame(height: DesignTokens.Chrome.tabStripHeight)
        .onPreferenceChange(TabContentWidthKey.self) { contentWidth = $0 }
        .onPreferenceChange(TabStripWidthKey.self) { viewportWidth = $0 }
        .animation(.easeInOut(duration: 0.15), value: isOverflowing)
        .background(.thinMaterial)
        .clipped()
        .background(WindowAccessor { window in
            // Register so a tab dropped on this window (from any window) routes here.
            if let window { TabTearOffCoordinator.shared.register(window: window, workspace: workspace) }
        })
    }

    /// A drop onto a chip: an in-window tab reorders to that slot; a tab dragged
    /// from *another* window is inserted at that slot (cross-window move honoring
    /// the drop position).
    private func reorder(_ draggedID: UUID, toPositionOf targetID: UUID) {
        if workspace.tabs.contains(where: { $0.id == draggedID }) {
            workspace.moveTab(draggedID, toPositionOf: targetID)
        } else {
            TabTearOffCoordinator.shared.moveInFlightTab(toPositionOf: targetID, into: workspace)
        }
    }
}

/// A chevron menu shown at the trailing edge of the tab strip when the tabs
/// overflow the visible width, listing every open tab so any can be jumped to.
private struct TabOverflowMenu: View {
    @Bindable var workspace: WorkspaceModel

    var body: some View {
        Menu {
            ForEach(workspace.tabs) { tab in
                Button {
                    workspace.selectTab(tab.id)
                } label: {
                    Label(
                        tab.displayTitle + (tab.document.isDirty ? " ●" : ""),
                        systemImage: tab.id == workspace.activeTabID ? "checkmark" : "doc"
                    )
                }
            }
        } label: {
            Image(systemName: "chevron.down")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.secondary)
                .frame(width: 30, height: DesignTokens.Chrome.tabStripHeight)
                .contentShape(Rectangle())
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .frame(width: 30)
        .background(.thinMaterial)
        .overlay(alignment: .leading) { Divider() }
        .help("Show all tabs")
        .accessibilityLabel("Show all tabs")
    }
}

/// Path breadcrumb under the tab strip: workspace ▸ folders ▸ file.
/// Folder segments reveal that folder in the file tree; the
/// file segment reveals the current document. Falls back to just the name for
/// untitled buffers or files outside the workspace root.
private struct BreadcrumbBar: View {
    @Bindable var workspace: WorkspaceModel

    private struct Segment: Identifiable {
        let name: String
        let url: URL?
        let isDirectory: Bool
        let isLast: Bool
        // Stable identity (path, or the name for untitled buffers) so ForEach
        // doesn't churn every render — a fresh UUID here rebuilt the whole bar.
        var id: String { url?.path ?? name }
    }

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 3) {
                ForEach(segments) { seg in
                    segmentButton(seg)
                    if !seg.isLast {
                        Image(systemName: "chevron.compact.right")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                }
            }
            .padding(.horizontal, 12)
        }
        .scrollEdgeEffectStyle(.hard, for: .horizontal)
        .frame(height: 24)
        .background(.bar)
    }

    @ViewBuilder
    private func segmentButton(_ seg: Segment) -> some View {
        Button {
            if let url = seg.url {
                workspace.revealInFileTree(url, isDirectory: seg.isDirectory)
            }
        } label: {
            HStack(spacing: 4) {
                if seg.isLast, let doc = workspace.activeTab?.document {
                    FileTypeIcon(url: doc.fileURL, isDirectory: false, language: doc.language, size: 13)
                }
                Text(seg.name)
                    .font(.caption)
                    .foregroundStyle(seg.isLast ? .primary : .secondary)
                    .lineLimit(1)
            }
        }
        .buttonStyle(.plain)
        .disabled(seg.url == nil)
        .help(seg.url?.path ?? seg.name)
    }

    private var segments: [Segment] {
        guard let doc = workspace.activeTab?.document else { return [] }
        guard let fileURL = doc.fileURL else {
            return [Segment(name: doc.displayName, url: nil, isDirectory: false, isLast: true)]
        }
        let std = fileURL.standardizedFileURL
        if let root = workspace.rootURL?.standardizedFileURL,
           std.path.hasPrefix(root.path + "/") {
            let relative = String(std.path.dropFirst(root.path.count + 1))
            let parts = relative.split(separator: "/").map(String.init)
            var result: [Segment] = [
                Segment(name: root.lastPathComponent, url: root, isDirectory: true, isLast: parts.isEmpty)
            ]
            var url = root
            for (i, part) in parts.enumerated() {
                url = url.appendingPathComponent(part)
                let isLast = i == parts.count - 1
                result.append(Segment(name: part, url: url, isDirectory: !isLast, isLast: isLast))
            }
            return result
        }
        // Outside the workspace root: parent folder + file name.
        let parent = std.deletingLastPathComponent()
        return [
            Segment(name: parent.lastPathComponent, url: parent, isDirectory: true, isLast: false),
            Segment(name: std.lastPathComponent, url: std, isDirectory: false, isLast: true),
        ]
    }
}

private struct TabChip: View {
    let tab: EditorTab
    let isActive: Bool
    let onSelect: () -> Void
    let onClose: () -> Void
    let onCloseOthers: () -> Void
    let onCloseRight: () -> Void
    let onCloseAll: () -> Void
    let onOpenSplitPreview: () -> Void
    /// Builds the `.draggable` payload for the tab (registers the in-flight drag
    /// with the coordinator).
    let makeTransfer: () -> TabTransfer
    /// Reorders the dragged tab (its id) to this chip's slot — in-strip reorder.
    let onReorder: (UUID) -> Void
    @State private var isDropTargeted = false

    var body: some View {
        // The chip is a plain hittable surface (not a `Button`): a SwiftUI
        // `Button` swallows drag events. Selection is a simultaneous `TapGesture`;
        // the drag is `.draggable` — the exact native drag path the file tree uses
        // (`.draggable(node.url)`), which is the only mechanism that fires inside
        // the tab strip's `ScrollView` (`.onDrag` and a `DragGesture` both stayed
        // inert there). `contentShape` makes the whole area (incl. padding and the
        // trailing reserve) hittable; the close button overlays the reserve on top
        // so it still gets its own clicks.
        HStack(spacing: 6) {
            if let special = tab.special {
                Image(systemName: special.symbol)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.tint)
                    .frame(width: 14)
            } else {
                FileTypeIcon(url: tab.document.fileURL, isDirectory: false, language: tab.document.language, size: 14)
            }
            Text(tab.displayTitle)
                .foregroundStyle(isActive ? .primary : .secondary)
                .lineLimit(1)
                .truncationMode(.middle)
                .frame(minWidth: 80, idealWidth: 140, maxWidth: DesignTokens.Chrome.labelMaxWidth, alignment: .leading)
            if tab.special == nil, tab.document.isDirty {
                Circle().frame(width: 6, height: 6).foregroundStyle(.tint)
            }
        }
        .padding(.leading, 10)
        .padding(.trailing, 28)
        .frame(height: DesignTokens.Chrome.tabStripHeight)
        .contentShape(Rectangle())
        .accessibilityLabel("Select \(tab.displayTitle)")
        .accessibilityAddTraits(.isButton)
        .accessibilityAction { onSelect() }
        .animation(.easeInOut(duration: 0.15), value: isActive)
        // Native "front tab" look: the active tab reads as a raised surface
        // (matching the editor area) instead of an accent wash, with a thin
        // accent hairline along its top edge — the Xcode/Safari idiom.
        .background {
            Color(nsColor: .controlBackgroundColor).opacity(isActive ? 1 : 0)
        }
        .overlay(alignment: .top) {
            Rectangle().fill(.tint).frame(height: 2).opacity(isActive ? 1 : 0)
        }
        .overlay(alignment: .trailing) {
            Button(action: onClose) {
                Image(systemName: "xmark")
                    .imageScale(.small)
            }
            .buttonStyle(.plain)
            .opacity(0.6)
            .padding(.trailing, 10)
            .help("Close \(tab.document.displayName)")
            .accessibilityLabel("Close \(tab.document.displayName)")
        }
        // Drag pulls the tab out (native `.draggable`, fires in the ScrollView).
        // The drag image is a small chip with the tab's name.
        .draggable(makeTransfer()) {
            TabDragPreview(tab: tab)
        }
        // Selection is a *simultaneous* TapGesture, NOT `.onTapGesture`: on macOS
        // `.onTapGesture` wins the mouse-down arbitration and blocks the drag from
        // ever starting. A simultaneous tap runs alongside the drag instead.
        .simultaneousGesture(TapGesture().onEnded { onSelect() })
        // Dropping a tab onto this chip reorders it into this slot (in-strip
        // reorder). A drop within the same window no-ops in `finishDrag`, so the
        // reorder and tear-off paths don't fight. The leading bar shows where the
        // dragged tab will land.
        .dropDestination(for: TabTransfer.self) { items, _ in
            guard let draggedID = items.first?.tabID else { return false }
            onReorder(draggedID)
            return true
        } isTargeted: { targeted in
            withAnimation(.easeOut(duration: 0.12)) { isDropTargeted = targeted }
        }
        .overlay(alignment: .leading) {
            Capsule()
                .fill(.tint)
                .frame(width: 3)
                .padding(.vertical, 5)
                .opacity(isDropTargeted ? 1 : 0)
                .scaleEffect(y: isDropTargeted ? 1 : 0.4, anchor: .center)
        }
        .contextMenu {
            Button("Close") { onClose() }
            Button("Close Other Tabs") { onCloseOthers() }
            Button("Close Tabs to the Right") { onCloseRight() }
            Button("Close All Tabs") { onCloseAll() }
            if tab.document.fileURL.map(SplitPreviewContent.supports) == true {
                Divider()
                Button("Open in Split Preview") { onOpenSplitPreview() }
            }
        }
    }
}

/// The drag image shown under the cursor while a tab is dragged. Mirrors the
/// chip's leading content (file-type icon + title).
private struct TabDragPreview: View {
    let tab: EditorTab

    var body: some View {
        HStack(spacing: 6) {
            if let special = tab.special {
                Image(systemName: special.symbol)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.tint)
            } else {
                FileTypeIcon(url: tab.document.fileURL, isDirectory: false, language: tab.document.language, size: 14)
            }
            Text(tab.displayTitle)
                .font(.callout)
                .lineLimit(1)
        }
        .padding(.horizontal, 12)
        .frame(height: 30)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
    }
}

/// Compact error/warning counts in the status bar; hidden when the file is clean.
private struct DiagnosticSummary: View {
    let diagnostics: [Diagnostic]

    /// Error and warning tallies in a single pass, instead of filtering the
    /// array twice on every status-bar render.
    private var counts: (errors: Int, warnings: Int) {
        diagnostics.reduce(into: (0, 0)) { acc, diagnostic in
            switch diagnostic.severity {
            case .error: acc.0 += 1
            case .warning: acc.1 += 1
            default: break
            }
        }
    }

    var body: some View {
        let counts = counts
        if counts.errors > 0 || counts.warnings > 0 {
            HStack(spacing: DesignTokens.Spacing.medium) {
                if counts.errors > 0 {
                    Label("\(counts.errors)", systemImage: "xmark.octagon.fill")
                        .foregroundStyle(.red)
                }
                if counts.warnings > 0 {
                    Label("\(counts.warnings)", systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                }
            }
            .font(DesignTokens.Typography.statusNumeric)
            .labelStyle(.titleAndIcon)
        }
    }
}

/// Clickable language label in the status bar: opens a menu of every
/// supported syntax, with an "Auto-detect" option that clears the manual choice.
private struct LanguagePicker: View {
    let document: TextDocument

    var body: some View {
        Menu {
            LanguageMenuItems(document: document)
        } label: {
            Text(document.language.rawValue)
                .font(DesignTokens.Typography.statusLabel)
                .foregroundStyle(.secondary)
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .help("Select syntax language")
    }
}

private struct StatusBar: View {
    let workspace: WorkspaceModel

    var body: some View {
        HStack(spacing: DesignTokens.Spacing.large) {
            if let doc = workspace.activeTab?.document {
                Text(doc.displayName).font(DesignTokens.Typography.statusLabel)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .frame(maxWidth: DesignTokens.Chrome.labelMaxWidth, alignment: .leading)
                Text(encodingLabel(doc.encoding)).font(DesignTokens.Typography.statusLabel)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                LanguagePicker(document: doc)
                Text("Ln \(doc.cursorLine), Col \(doc.cursorColumn)").font(DesignTokens.Typography.statusNumeric).foregroundStyle(.secondary)
                    .lineLimit(1)
                Text(doc.fileSizeLabel).font(DesignTokens.Typography.statusNumeric).foregroundStyle(.secondary)
                    .lineLimit(1)
                Text(doc.isDirty ? "Modified" : "Saved").font(DesignTokens.Typography.statusLabel).foregroundStyle(.secondary)
                    .lineLimit(1)
                DiagnosticSummary(diagnostics: doc.diagnostics)
            }
            Spacer()
            GitStatusBarView(root: workspace.rootURL)
            if let doc = workspace.activeTab?.document {
                IntelliSenseStatusView(language: doc.language)
            }
        }
        .padding(.horizontal, DesignTokens.Spacing.large)
        .frame(height: DesignTokens.Chrome.statusBarHeight)
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
    @State private var window: NSWindow?

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
                .font(DesignTokens.Typography.statusLabel)
                .foregroundStyle(.secondary)
                .labelStyle(.titleAndIcon)
            }
        }
        .task(id: root) { await reload() }
        .onReceive(NotificationCenter.default.publisher(for: .gitDidChange)) { _ in
            Task { await reload() }
        }
        // Only this window's activation refreshes the status; a global
        // subscription made every window shell out `git status` on every key-up.
        .background(WindowAccessor { window = $0 })
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didBecomeKeyNotification)) { note in
            guard (note.object as? NSWindow) === window else { return }
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
                .font(DesignTokens.Typography.statusLabel)
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
