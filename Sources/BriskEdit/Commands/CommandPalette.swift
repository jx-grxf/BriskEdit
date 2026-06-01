import SwiftUI

struct CommandPaletteView: View {
    @Bindable var workspace: WorkspaceModel
    @State private var query: String = ""
    @State private var selection: EditorCommand.ID?
    @FocusState private var fieldFocused: Bool

    private var results: [EditorCommand] { CommandRegistry.filtered(query) }

    var body: some View {
        VStack(spacing: 0) {
            TextField("Type a command", text: $query)
                .textFieldStyle(.plain)
                .font(.system(size: 16))
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .focused($fieldFocused)
                .onSubmit { runSelection() }
            Divider()
            List(selection: $selection) {
                ForEach(results) { command in
                    Button {
                        selection = command.id
                        runSelection()
                    } label: {
                        HStack {
                            Text(command.title)
                            Spacer()
                            Text(command.group).foregroundStyle(.secondary).font(.caption)
                            if let s = command.shortcut {
                                Text(s).foregroundStyle(.secondary).font(.caption.monospaced())
                            }
                        }
                    }
                    .buttonStyle(.plain)
                    .tag(command.id)
                }
            }
            .listStyle(.plain)
            .frame(minHeight: 280)
        }
        .frame(width: 520)
        .onAppear {
            fieldFocused = true
            selection = results.first?.id
        }
        .onChange(of: query) { _, _ in
            selection = results.first?.id
        }
        .onExitCommand { workspace.showCommandPalette = false }
    }

    private func runSelection() {
        guard let id = selection, let command = results.first(where: { $0.id == id }) else { return }
        workspace.showCommandPalette = false
        command.perform(workspace)
    }
}
