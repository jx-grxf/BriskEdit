import Foundation
import Observation

struct TerminalInputRequest: Equatable, Sendable {
    let id = UUID()
    let text: String
}

@MainActor
@Observable
final class TerminalController {
    var title: String = "Terminal"
    var isRunning: Bool = false
    var currentDirectory: URL = FileManager.default.homeDirectoryForCurrentUser
    var restartToken = UUID()
    var pendingInput: TerminalInputRequest?

    var shellExecutable: String {
        let shell = ProcessInfo.processInfo.environment["SHELL"] ?? "/bin/zsh"
        return shell.isEmpty ? "/bin/zsh" : shell
    }

    var shellArguments: [String] {
        ["-l"]
    }

    var shellDisplayName: String {
        URL(fileURLWithPath: shellExecutable).lastPathComponent
    }

    var environmentVariables: [String] {
        var environment = ProcessInfo.processInfo.environment
        environment["TERM"] = "xterm-256color"
        environment["COLORTERM"] = "truecolor"
        environment["CLICOLOR"] = "1"
        environment["FORCE_COLOR"] = "1"
        environment["BRISKEDIT_TERMINAL"] = "1"
        return environment
            .map { "\($0.key)=\($0.value)" }
            .sorted()
    }

    func startShell(cwd: URL?) {
        currentDirectory = cwd ?? currentDirectory
        title = shellDisplayName
        isRunning = true
        restartToken = UUID()
    }

    func send(_ text: String) {
        pendingInput = TerminalInputRequest(text: text)
    }

    func sendLine(_ text: String) {
        send(text.hasSuffix("\n") ? text : text + "\n")
    }

    func runActiveDocument(_ document: TextDocument?, workspaceRoot: URL?) {
        do {
            let command = try RunService.resolve(document: document, workspaceRoot: workspaceRoot)
            currentDirectory = command.cwd
            title = command.title
            if !isRunning {
                startShell(cwd: command.cwd)
            }
            sendLine("cd \(RunService.shellQuote(command.cwd.path)) && \(command.shellLine)")
        } catch {
            if !isRunning {
                startShell(cwd: workspaceRoot)
            }
            sendLine("printf '%s\\n' \(RunService.shellQuote(error.localizedDescription))")
        }
    }

    func clear() {
        send("\u{0C}")
    }

    func markTerminated() {
        isRunning = false
    }
}
