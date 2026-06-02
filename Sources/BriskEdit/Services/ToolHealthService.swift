import Foundation

enum ToolCategory: String, CaseIterable, Sendable {
    case runner = "Run"
    case languageServer = "Language Server"
    case formatter = "Formatter"
}

struct ToolDescriptor: Identifiable, Sendable, Hashable {
    let id: String
    let name: String
    let category: ToolCategory
    let probeCommand: String
    let usedFor: String
    let installHint: String
    let installCommand: String?
}

struct ToolHealthItem: Identifiable, Sendable, Hashable {
    let descriptor: ToolDescriptor
    let path: String?

    var id: String { descriptor.id }
    var isAvailable: Bool { path != nil }
}

enum ToolHealthService {
    static let descriptors: [ToolDescriptor] = [
        ToolDescriptor(id: "run.clang", name: "clang", category: .runner, probeCommand: "xcrun --find clang", usedFor: "C single-file builds", installHint: "Install Xcode Command Line Tools.", installCommand: "xcode-select --install"),
        ToolDescriptor(id: "run.clang++", name: "clang++", category: .runner, probeCommand: "xcrun --find clang++", usedFor: "C++ single-file builds", installHint: "Install Xcode Command Line Tools.", installCommand: "xcode-select --install"),
        ToolDescriptor(id: "run.gcc", name: "gcc", category: .runner, probeCommand: "command -v gcc", usedFor: "C single-file builds", installHint: "Install GCC.", installCommand: "brew install gcc"),
        ToolDescriptor(id: "run.g++", name: "g++", category: .runner, probeCommand: "command -v g++", usedFor: "C++ single-file builds", installHint: "Install GCC.", installCommand: "brew install gcc"),
        ToolDescriptor(id: "run.swift", name: "swift", category: .runner, probeCommand: "xcrun --find swift", usedFor: "Swift scripts and SwiftPM projects", installHint: "Install Xcode or Swift toolchain.", installCommand: "xcode-select --install"),
        ToolDescriptor(id: "run.python3", name: "python3", category: .runner, probeCommand: "command -v python3", usedFor: "Python files", installHint: "Install Python 3.", installCommand: "brew install python"),
        ToolDescriptor(id: "run.node", name: "node", category: .runner, probeCommand: "command -v node", usedFor: "JavaScript files", installHint: "Install Node.js.", installCommand: "brew install node"),
        ToolDescriptor(id: "run.deno", name: "deno", category: .runner, probeCommand: "command -v deno", usedFor: "TypeScript fallback runner", installHint: "Install Deno.", installCommand: "brew install deno"),
        ToolDescriptor(id: "run.tsx", name: "tsx", category: .runner, probeCommand: "command -v tsx", usedFor: "TypeScript fallback runner", installHint: "Install tsx with npm.", installCommand: "npm install -g tsx"),
        ToolDescriptor(id: "run.go", name: "go", category: .runner, probeCommand: "command -v go", usedFor: "Go files and modules", installHint: "Install Go.", installCommand: "brew install go"),
        ToolDescriptor(id: "run.cargo", name: "cargo", category: .runner, probeCommand: "command -v cargo", usedFor: "Rust projects", installHint: "Install Rust via rustup.", installCommand: "brew install rust"),
        ToolDescriptor(id: "run.rustc", name: "rustc", category: .runner, probeCommand: "command -v rustc", usedFor: "Rust single-file builds", installHint: "Install Rust via rustup.", installCommand: "brew install rust"),

        ToolDescriptor(id: "lsp.clangd", name: "clangd", category: .languageServer, probeCommand: "xcrun --find clangd", usedFor: "C and C++ completions and diagnostics", installHint: "Install Xcode Command Line Tools.", installCommand: "xcode-select --install"),
        ToolDescriptor(id: "lsp.sourcekit", name: "sourcekit-lsp", category: .languageServer, probeCommand: "xcrun --find sourcekit-lsp", usedFor: "Swift completions and diagnostics", installHint: "Install Xcode or Swift toolchain.", installCommand: "xcode-select --install"),
        ToolDescriptor(id: "lsp.gopls", name: "gopls", category: .languageServer, probeCommand: "command -v gopls", usedFor: "Go completions and diagnostics", installHint: "Install gopls.", installCommand: "go install golang.org/x/tools/gopls@latest"),
        ToolDescriptor(id: "lsp.pyright", name: "pyright-langserver", category: .languageServer, probeCommand: "command -v pyright-langserver", usedFor: "Python completions and diagnostics", installHint: "Install pyright.", installCommand: "npm install -g pyright"),
        ToolDescriptor(id: "lsp.rust-analyzer", name: "rust-analyzer", category: .languageServer, probeCommand: "command -v rust-analyzer", usedFor: "Rust completions and diagnostics", installHint: "Install rust-analyzer.", installCommand: "brew install rust-analyzer"),
        ToolDescriptor(id: "lsp.typescript", name: "typescript-language-server", category: .languageServer, probeCommand: "command -v typescript-language-server", usedFor: "JS/TS completions and diagnostics", installHint: "Install typescript-language-server.", installCommand: "npm install -g typescript typescript-language-server"),

        ToolDescriptor(id: "fmt.clang-format", name: "clang-format", category: .formatter, probeCommand: "command -v clang-format", usedFor: "C and C++ format-on-save", installHint: "Install clang-format.", installCommand: "brew install clang-format"),
        ToolDescriptor(id: "fmt.swift-format", name: "swift-format", category: .formatter, probeCommand: "command -v swift-format", usedFor: "Swift format-on-save", installHint: "Install swift-format.", installCommand: "brew install swift-format"),
        ToolDescriptor(id: "fmt.gofmt", name: "gofmt", category: .formatter, probeCommand: "command -v gofmt", usedFor: "Go format-on-save", installHint: "Install Go.", installCommand: "brew install go"),
        ToolDescriptor(id: "fmt.rustfmt", name: "rustfmt", category: .formatter, probeCommand: "command -v rustfmt", usedFor: "Rust format-on-save", installHint: "Install Rust via rustup.", installCommand: "brew install rust"),
        ToolDescriptor(id: "fmt.black", name: "black", category: .formatter, probeCommand: "command -v black", usedFor: "Python format-on-save", installHint: "Install black.", installCommand: "python3 -m pip install --user black"),
        ToolDescriptor(id: "fmt.prettier", name: "prettier", category: .formatter, probeCommand: "command -v prettier", usedFor: "Web and Markdown format-on-save", installHint: "Install prettier.", installCommand: "npm install -g prettier")
    ]

    static func snapshot() async -> [ToolHealthItem] {
        await Task.detached(priority: .utility) {
            descriptors.map { descriptor in
                ToolHealthItem(descriptor: descriptor, path: probe(descriptor.probeCommand))
            }
        }.value
    }

    static func descriptor(id: String) -> ToolDescriptor? {
        descriptors.first { $0.id == id }
    }

    static func missingRunRequirements(for language: SourceLanguage, workspaceRoot: URL?) async -> [[ToolDescriptor]] {
        let groups = runRequirementGroups(for: language, workspaceRoot: workspaceRoot)
        return await Task.detached(priority: .utility) {
            groups.filter { group in
                group.allSatisfy { probe($0.probeCommand) == nil }
            }
        }.value
    }

    static func install(_ descriptor: ToolDescriptor) async -> GitResult {
        guard let command = descriptor.installCommand else {
            return GitResult(ok: false, output: descriptor.installHint)
        }
        return await runInstall(command)
    }

    private static func runRequirementGroups(for language: SourceLanguage, workspaceRoot: URL?) -> [[ToolDescriptor]] {
        func group(_ ids: [String]) -> [ToolDescriptor] { ids.compactMap(descriptor(id:)) }
        switch language {
        case .c:
            return [group(["run.clang", "run.gcc"])]
        case .cpp:
            return [group(["run.clang++", "run.g++"])]
        case .swift:
            return [group(["run.swift"])]
        case .python:
            return [group(["run.python3"])]
        case .javascript:
            return [group(["run.node"])]
        case .typescript:
            return [group(["run.deno", "run.tsx"])]
        case .go:
            return [group(["run.go"])]
        case .rust:
            return [group(["run.cargo", "run.rustc"])]
        default:
            return []
        }
    }

    private static func probe(_ command: String) -> String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/zsh")
        process.arguments = ["-lc", command]
        let stdout = Pipe()
        process.standardOutput = stdout
        process.standardError = FileHandle.nullDevice
        do { try process.run() } catch { return nil }
        let data = stdout.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else { return nil }
        let output = String(data: data, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return output?.isEmpty == false ? output : nil
    }

    private static func runInstall(_ command: String) async -> GitResult {
        await Task.detached(priority: .userInitiated) {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/bin/zsh")
            process.arguments = ["-lc", command]
            // Funnel stdout *and* stderr into one pipe and drain it in a single
            // pass. Using two pipes and reading them sequentially deadlocks when a
            // chatty installer (go install gopls, pip black, brew) fills the
            // second pipe's buffer while we're still blocked reading the first —
            // which made those installs hang forever with the progress bar stuck.
            let pipe = Pipe()
            process.standardOutput = pipe
            process.standardError = pipe
            do { try process.run() } catch {
                return GitResult(ok: false, output: error.localizedDescription)
            }
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()
            let output = (String(data: data, encoding: .utf8) ?? "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            return GitResult(ok: process.terminationStatus == 0, output: output.isEmpty ? "Install command finished." : output)
        }.value
    }
}
