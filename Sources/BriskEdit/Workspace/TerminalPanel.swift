import AppKit
import SwiftTerm
import SwiftUI

struct TerminalPanel: View {
    @Bindable var workspace: WorkspaceModel

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Label(workspace.terminal.title, systemImage: "terminal")
                    .font(.caption.weight(.semibold))
                    .lineLimit(1)
                Text(workspace.terminal.currentDirectory.path)
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Spacer()
                Circle()
                    .fill(workspace.terminal.isRunning ? Color.green : Color.secondary)
                    .frame(width: 7, height: 7)
                Button("Run", systemImage: "play.fill") {
                    workspace.runActiveDocument()
                }
                .disabled(workspace.activeTab?.document.language.isRunnable != true)
                Button("New Shell", systemImage: "plus") {
                    workspace.terminal.startShell(cwd: workspace.rootURL)
                }
                Button("Clear", systemImage: "trash") {
                    workspace.terminal.clear()
                }
                Button("Close", systemImage: "xmark") {
                    workspace.showTerminal = false
                }
            }
            .buttonStyle(.borderless)
            .padding(.horizontal, 10)
            .frame(height: 34)
            .background(.bar)

            Divider()

            TerminalEmulatorView(terminal: workspace.terminal)
                .frame(minHeight: 160)
        }
        .task {
            if !workspace.terminal.isRunning {
                workspace.terminal.startShell(cwd: workspace.rootURL)
            }
        }
    }
}

private struct TerminalEmulatorView: NSViewRepresentable {
    @Bindable var terminal: TerminalController

    func makeCoordinator() -> Coordinator {
        Coordinator(terminal: terminal)
    }

    func makeNSView(context: Context) -> LocalProcessTerminalView {
        let view = LocalProcessTerminalView(frame: .zero)
        view.font = NSFont.monospacedSystemFont(ofSize: 12, weight: .regular)
        view.configureNativeColors()
        view.nativeBackgroundColor = .textBackgroundColor
        view.nativeForegroundColor = .textColor
        view.caretColor = .controlAccentColor
        view.processDelegate = context.coordinator
        context.coordinator.terminalView = view
        return view
    }

    func updateNSView(_ view: LocalProcessTerminalView, context: Context) {
        context.coordinator.terminal = terminal
        if context.coordinator.restartToken != terminal.restartToken {
            context.coordinator.restartToken = terminal.restartToken
            if view.process.running {
                view.terminate()
            }
            view.startProcess(
                executable: terminal.shellExecutable,
                args: terminal.shellArguments,
                environment: terminal.environmentVariables,
                execName: terminal.shellDisplayName,
                currentDirectory: terminal.currentDirectory.path
            )
            DispatchQueue.main.async {
                view.window?.makeFirstResponder(view)
            }
        }

        if let pendingInput = terminal.pendingInput,
           context.coordinator.lastInputID != pendingInput.id {
            context.coordinator.lastInputID = pendingInput.id
            let bytes = Array(pendingInput.text.utf8)
            view.process.send(data: ArraySlice(bytes))
            DispatchQueue.main.async {
                view.window?.makeFirstResponder(view)
            }
        }
    }

    final class Coordinator: NSObject, LocalProcessTerminalViewDelegate {
        var terminal: TerminalController
        weak var terminalView: LocalProcessTerminalView?
        var restartToken: UUID?
        var lastInputID: UUID?

        init(terminal: TerminalController) {
            self.terminal = terminal
        }

        func sizeChanged(source: LocalProcessTerminalView, newCols: Int, newRows: Int) {}

        func setTerminalTitle(source: LocalProcessTerminalView, title: String) {
            Task { @MainActor [terminal] in
                terminal.title = title.isEmpty ? terminal.shellDisplayName : title
            }
        }

        func hostCurrentDirectoryUpdate(source: TerminalView, directory: String?) {
            guard let directory, !directory.isEmpty else { return }
            // Shells emit OSC 7 with a `file://host/path` URL. Parse it so we
            // don't end up storing the literal `file://…` string as a path.
            let resolvedPath: String
            if directory.hasPrefix("file://"), let url = URL(string: directory) {
                resolvedPath = url.path
            } else {
                resolvedPath = directory
            }
            Task { @MainActor [terminal] in
                terminal.currentDirectory = URL(fileURLWithPath: resolvedPath)
            }
        }

        func processTerminated(source: TerminalView, exitCode: Int32?) {
            Task { @MainActor [terminal] in
                terminal.markTerminated()
            }
        }
    }
}
