import SwiftUI

extension LSPSymbol {
    /// OutlineGroup wants nil (not empty) for leaves.
    var childrenOptional: [LSPSymbol]? { children.isEmpty ? nil : children }
}

/// Symbol outline for the active file, populated from `textDocument/documentSymbol`.
/// Clicking a symbol jumps the editor to its definition. Refreshes when the
/// active tab changes; a manual refresh button picks up edits.
struct OutlineSidebarView: View {
    @Bindable var workspace: WorkspaceModel

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Outline").font(.caption.bold()).foregroundStyle(.secondary)
                Spacer()
                if workspace.isLoadingOutline {
                    ProgressView().controlSize(.small)
                }
                Button {
                    workspace.refreshOutline()
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .buttonStyle(.plain)
                .help("Refresh outline")
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            Divider()
            content
        }
        .onAppear { workspace.refreshOutline() }
        .onChange(of: workspace.activeTabID) { _, _ in workspace.refreshOutline() }
    }

    @ViewBuilder
    private var content: some View {
        if workspace.outlineSymbols.isEmpty {
            ContentUnavailableView {
                Label("No Symbols", systemImage: "list.bullet.indent")
            } description: {
                Text(workspace.activeTab == nil ? "Open a file to see its outline." : "No symbols, or no language server for this file.")
            }
        } else {
            List {
                OutlineGroup(workspace.outlineSymbols, children: \.childrenOptional) { symbol in
                    SymbolRow(symbol: symbol) { jump(to: symbol) }
                }
            }
            .listStyle(.sidebar)
        }
    }

    private func jump(to symbol: LSPSymbol) {
        guard let url = workspace.activeTab?.document.fileURL else { return }
        Task { await workspace.openFile(at: url, line: symbol.line, column: symbol.column) }
    }
}

private struct SymbolRow: View {
    let symbol: LSPSymbol
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: SymbolKind.icon(symbol.kind))
                    .foregroundStyle(SymbolKind.color(symbol.kind))
                    .frame(width: 16)
                Text(symbol.name).font(.caption).lineLimit(1)
                if let detail = symbol.detail {
                    Text(detail).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
                }
                Spacer()
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

/// Maps LSP `SymbolKind` codes to SF Symbols + a tint, à la VS Code's outline.
private enum SymbolKind {
    static func icon(_ kind: Int) -> String {
        switch kind {
        case 2, 3, 4: "shippingbox"            // module/namespace/package
        case 5: "cube"                         // class
        case 6, 9: "function"                  // method/constructor
        case 7, 8: "f.cursive"                 // property/field
        case 10, 22: "list.bullet.rectangle"   // enum/enum-member
        case 11: "point.3.connected.trianglepath.dotted" // interface
        case 12: "function"                    // function
        case 13: "v.square"                    // variable
        case 14: "c.square"                    // constant
        case 23: "cube.transparent"            // struct
        default: "circle.fill"
        }
    }

    static func color(_ kind: Int) -> Color {
        switch kind {
        case 5, 23: .orange                    // class/struct
        case 6, 9, 12: .purple                 // method/function
        case 7, 8, 13: .blue                   // property/field/variable
        case 10, 11, 22: .teal                 // enum/interface
        case 14: .pink                         // constant
        default: .secondary
        }
    }
}
