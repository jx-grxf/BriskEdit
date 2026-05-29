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
}

struct ToolHealthItem: Identifiable, Sendable, Hashable {
    let descriptor: ToolDescriptor
    let path: String?

    var id: String { descriptor.id }
    var isAvailable: Bool { path != nil }
}

enum ToolHealthService {
    static let descriptors: [ToolDescriptor] = [
        ToolDescriptor(id: "run.clang", name: "clang", category: .runner, probeCommand: "xcrun --find clang", usedFor: "C and C++ single-file builds", installHint: "Install Xcode Command Line Tools."),
        ToolDescriptor(id: "run.swift", name: "swift", category: .runner, probeCommand: "xcrun --find swift", usedFor: "Swift scripts and SwiftPM projects", installHint: "Install Xcode or Swift toolchain."),
        ToolDescriptor(id: "run.python3", name: "python3", category: .runner, probeCommand: "command -v python3", usedFor: "Python files", installHint: "Install Python 3."),
        ToolDescriptor(id: "run.node", name: "node", category: .runner, probeCommand: "command -v node", usedFor: "JavaScript files", installHint: "Install Node.js."),
        ToolDescriptor(id: "run.deno", name: "deno", category: .runner, probeCommand: "command -v deno", usedFor: "TypeScript fallback runner", installHint: "Install Deno."),
        ToolDescriptor(id: "run.tsx", name: "tsx", category: .runner, probeCommand: "command -v tsx", usedFor: "TypeScript fallback runner", installHint: "Install tsx with npm."),
        ToolDescriptor(id: "run.go", name: "go", category: .runner, probeCommand: "command -v go", usedFor: "Go files and modules", installHint: "Install Go."),
        ToolDescriptor(id: "run.cargo", name: "cargo", category: .runner, probeCommand: "command -v cargo", usedFor: "Rust projects", installHint: "Install Rust via rustup."),
        ToolDescriptor(id: "run.rustc", name: "rustc", category: .runner, probeCommand: "command -v rustc", usedFor: "Rust single-file builds", installHint: "Install Rust via rustup."),

        ToolDescriptor(id: "lsp.clangd", name: "clangd", category: .languageServer, probeCommand: "xcrun --find clangd", usedFor: "C and C++ completions and diagnostics", installHint: "Install Xcode Command Line Tools."),
        ToolDescriptor(id: "lsp.sourcekit", name: "sourcekit-lsp", category: .languageServer, probeCommand: "xcrun --find sourcekit-lsp", usedFor: "Swift completions and diagnostics", installHint: "Install Xcode or Swift toolchain."),
        ToolDescriptor(id: "lsp.gopls", name: "gopls", category: .languageServer, probeCommand: "command -v gopls", usedFor: "Go completions and diagnostics", installHint: "Install gopls."),
        ToolDescriptor(id: "lsp.pyright", name: "pyright-langserver", category: .languageServer, probeCommand: "command -v pyright-langserver", usedFor: "Python completions and diagnostics", installHint: "Install pyright."),
        ToolDescriptor(id: "lsp.rust-analyzer", name: "rust-analyzer", category: .languageServer, probeCommand: "command -v rust-analyzer", usedFor: "Rust completions and diagnostics", installHint: "Install rust-analyzer."),
        ToolDescriptor(id: "lsp.typescript", name: "typescript-language-server", category: .languageServer, probeCommand: "command -v typescript-language-server", usedFor: "JS/TS completions and diagnostics", installHint: "Install typescript-language-server."),

        ToolDescriptor(id: "fmt.clang-format", name: "clang-format", category: .formatter, probeCommand: "command -v clang-format", usedFor: "C and C++ format-on-save", installHint: "Install clang-format."),
        ToolDescriptor(id: "fmt.swift-format", name: "swift-format", category: .formatter, probeCommand: "command -v swift-format", usedFor: "Swift format-on-save", installHint: "Install swift-format."),
        ToolDescriptor(id: "fmt.gofmt", name: "gofmt", category: .formatter, probeCommand: "command -v gofmt", usedFor: "Go format-on-save", installHint: "Install Go."),
        ToolDescriptor(id: "fmt.rustfmt", name: "rustfmt", category: .formatter, probeCommand: "command -v rustfmt", usedFor: "Rust format-on-save", installHint: "Install Rust via rustup."),
        ToolDescriptor(id: "fmt.black", name: "black", category: .formatter, probeCommand: "command -v black", usedFor: "Python format-on-save", installHint: "Install black."),
        ToolDescriptor(id: "fmt.prettier", name: "prettier", category: .formatter, probeCommand: "command -v prettier", usedFor: "Web and Markdown format-on-save", installHint: "Install prettier.")
    ]

    static func snapshot() async -> [ToolHealthItem] {
        await Task.detached(priority: .utility) {
            descriptors.map { descriptor in
                ToolHealthItem(descriptor: descriptor, path: probe(descriptor.probeCommand))
            }
        }.value
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
}
