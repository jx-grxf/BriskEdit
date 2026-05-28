import SwiftUI

struct EditorTabsView: View {
    @Bindable var workspace: WorkspaceModel
    @Environment(Preferences.self) private var preferences
    @SceneStorage("workspace.terminalHeight") private var terminalHeight: Double = 260
    @State private var terminalResizeStart: Double?

    var body: some View {
        VStack(spacing: 0) {
            TabStrip(workspace: workspace)
            Divider()
            if let tab = workspace.activeTab {
                GeometryReader { proxy in
                    VStack(spacing: 0) {
                        editorSurface(for: tab)
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
        if workspace.showMarkdownPreview && tab.document.language == .markdown {
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
                        onClose: { workspace.closeTab(tab.id) }
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
            Image(systemName: tab.document.language.iconName)
                .foregroundStyle(languageColor(tab.document.language))
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

    private func languageColor(_ language: SourceLanguage) -> Color {
        switch language {
        case .swift: .orange
        case .c, .cpp: .blue
        case .javascript, .typescript: .yellow
        case .php: .indigo
        case .python: .green
        case .rust: .brown
        case .markdown: .purple
        case .json, .yaml: .cyan
        case .html, .css, .xml: .pink
        case .shell: .mint
        case .go: .teal
        case .plainText: .secondary
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
