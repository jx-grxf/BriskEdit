import SwiftUI

struct EditorTabsView: View {
    @Bindable var workspace: WorkspaceModel
    @Environment(Preferences.self) private var preferences
    @SceneStorage("workspace.terminalHeight") private var terminalHeight: Double = 260
    @State private var terminalResizeStart: Double?
    @SceneStorage("workspace.pdfSplitWidth") private var pdfSplitWidth: Double = 400
    @State private var pdfResizeStart: Double?

    var body: some View {
        VStack(spacing: 0) {
            TabStrip(workspace: workspace)
            Divider()
            if let tab = workspace.activeTab {
                GeometryReader { proxy in
                    VStack(spacing: 0) {
                        if tab.document.externalChangePending {
                            ExternalChangeBanner(document: tab.document)
                        }
                        HStack(spacing: 0) {
                            editorSurface(for: tab)
                                .frame(minWidth: 320)
                                .layoutPriority(1)
                            if let pdf = workspace.splitPDFURL {
                                PDFSplitHandle()
                                    .gesture(resizePDFGesture(maxWidth: proxy.size.width - 360))
                                SplitPDFPane(url: pdf) { workspace.splitPDFURL = nil }
                                    .frame(width: clampedPDFWidth(maxWidth: proxy.size.width - 360))
                                    .layoutPriority(0)
                            }
                        }
                        .frame(minHeight: 180)
                        .layoutPriority(1)
                        if workspace.showTerminal {
                            TerminalResizeHandle()
                                .gesture(resizeTerminalGesture(maxHeight: proxy.size.height - 180))
                            TerminalPanel(workspace: workspace)
                                .frame(height: clampedTerminalHeight(maxHeight: proxy.size.height - 180))
                                .layoutPriority(0)
                        }
                    }
                }
            } else {
                ContentUnavailableView {
                    Label("No Active Tab", systemImage: "exclamationmark.triangle")
                } description: {
                    Text("Select a tab or open a file.")
                }
            }
            Divider()
            StatusBar(workspace: workspace)
        }
    }

    private func clampedPDFWidth(maxWidth: CGFloat) -> CGFloat {
        min(max(CGFloat(pdfSplitWidth), 240), max(280, maxWidth))
    }

    private func resizePDFGesture(maxWidth: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 1)
            .onChanged { value in
                let start = pdfResizeStart ?? pdfSplitWidth
                pdfResizeStart = start
                let proposed = start - Double(value.translation.width)
                pdfSplitWidth = Double(min(max(CGFloat(proposed), 240), max(280, maxWidth)))
            }
            .onEnded { _ in pdfResizeStart = nil }
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
                terminalHeight = Double(min(max(CGFloat(proposed), 140), max(180, maxHeight)))
            }
            .onEnded { _ in
                terminalResizeStart = nil
            }
    }

    @ViewBuilder
    private func editorSurface(for tab: EditorTab) -> some View {
        if let pdfURL = tab.pdfURL {
            PDFViewerHost(url: pdfURL)
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

private struct PDFSplitHandle: View {
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
        .accessibilityLabel("Resize PDF pane")
    }
}

private struct SplitPDFPane: View {
    let url: URL
    let onClose: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 6) {
                Image(systemName: "doc.richtext")
                Text(url.lastPathComponent)
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
            PDFViewerHost(url: url)
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
        .frame(height: 32)
        .background(.thinMaterial)
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
