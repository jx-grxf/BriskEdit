import SwiftUI

struct EditorTabsView: View {
    @Bindable var workspace: WorkspaceModel
    @Environment(Preferences.self) private var preferences

    var body: some View {
        VStack(spacing: 0) {
            TabStrip(workspace: workspace)
            Divider()
            if let tab = workspace.activeTab {
                EditorHost(document: tab.document, theme: preferences.editorTheme)
                    .id(tab.id)
            } else {
                Color.clear
            }
            Divider()
            StatusBar(workspace: workspace)
        }
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
            Text(tab.document.displayName)
                .lineLimit(1)
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

private struct StatusBar: View {
    let workspace: WorkspaceModel

    var body: some View {
        HStack(spacing: 12) {
            if let doc = workspace.activeTab?.document {
                Text(doc.displayName).font(.caption.monospaced())
                Text(encodingLabel(doc.encoding)).font(.caption.monospaced())
                Text(doc.isDirty ? "Modified" : "Saved").font(.caption.monospaced()).foregroundStyle(.secondary)
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
