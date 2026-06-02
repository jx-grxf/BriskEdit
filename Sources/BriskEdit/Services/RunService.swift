import Foundation

struct RunCommand: Sendable {
    let title: String
    let shellLine: String
    let cwd: URL
}

enum RunService {
    @MainActor
    static func resolve(document: TextDocument?, workspaceRoot: URL?) async throws -> RunCommand {
        guard let document else { throw RunError.noDocument }
        guard document.language.isRunnable else { throw RunError.unsupported(document.language.rawValue) }

        if requiresSaveBeforeRun(document: document, workspaceRoot: workspaceRoot) {
            throw RunError.needsSavedProjectFile(document.displayName)
        }

        let source = try await materializedSource(for: document)
        let sourceURL = source.url
        let cwd = runDirectory(for: sourceURL, workspaceRoot: workspaceRoot)
        let file = shellQuote(sourceURL.path)
        let cleanup = source.cleanupAfterRun ? " ; rm -f \(file)" : ""

        let line: String
        switch document.language {
        case .c:
            let output = shellQuote(tempBinaryPath())
            line = "(xcrun clang \(file) -Wall -Wextra -DprintDih=printf -o \(output) && \(output)); __brisk_status=$?; rm -f \(output)\(cleanup); printf '\\n[exit %s]\\n' \"$__brisk_status\""
        case .cpp:
            let output = shellQuote(tempBinaryPath())
            line = "(xcrun clang++ \(file) -Wall -Wextra -std=c++20 -o \(output) && \(output)); __brisk_status=$?; rm -f \(output)\(cleanup); printf '\\n[exit %s]\\n' \"$__brisk_status\""
        case .swift:
            if let packageRoot = ancestor(containing: "Package.swift", from: sourceURL.deletingLastPathComponent(), stopAt: workspaceRoot) {
                return RunCommand(title: "swift run", shellLine: "swift run", cwd: packageRoot)
            }
            line = "swift \(file)\(cleanup)"
        case .python:
            line = "python3 \(file)\(cleanup)"
        case .javascript:
            line = "node \(file)\(cleanup)"
        case .typescript:
            line = "if command -v deno >/dev/null 2>&1; then deno run \(file); elif command -v tsx >/dev/null 2>&1; then tsx \(file); else echo 'BriskEdit: install deno or tsx to run TypeScript files.'; false; fi\(cleanup)"
        case .shell:
            line = "chmod +x \(file) 2>/dev/null || true; \(file)\(cleanup)"
        case .ruby:
            line = "ruby \(file)\(cleanup)"
        case .lua:
            line = "lua \(file)\(cleanup)"
        case .perl:
            line = "perl \(file)\(cleanup)"
        case .go:
            if ancestor(containing: "go.mod", from: sourceURL.deletingLastPathComponent(), stopAt: workspaceRoot) != nil {
                line = "go run ."
            } else {
                line = "go run \(file)\(cleanup)"
            }
        case .rust:
            if let cargoRoot = ancestor(containing: "Cargo.toml", from: sourceURL.deletingLastPathComponent(), stopAt: workspaceRoot) {
                return RunCommand(title: "cargo run", shellLine: "cargo run", cwd: cargoRoot)
            }
            let output = shellQuote(tempBinaryPath())
            line = "(rustc \(file) -o \(output) && \(output)); __brisk_status=$?; rm -f \(output)\(cleanup); printf '\\n[exit %s]\\n' \"$__brisk_status\""
        default:
            throw RunError.unsupported(document.language.rawValue)
        }

        return RunCommand(title: "Run \(document.displayName)", shellLine: line, cwd: cwd)
    }

    @MainActor
    static func requiresSaveBeforeRun(document: TextDocument, workspaceRoot: URL?) -> Bool {
        guard document.isDirty, let fileURL = document.fileURL else { return false }
        switch document.language {
        case .swift:
            return ancestor(containing: "Package.swift", from: fileURL.deletingLastPathComponent(), stopAt: workspaceRoot) != nil
        case .go:
            return ancestor(containing: "go.mod", from: fileURL.deletingLastPathComponent(), stopAt: workspaceRoot) != nil
        case .rust:
            return ancestor(containing: "Cargo.toml", from: fileURL.deletingLastPathComponent(), stopAt: workspaceRoot) != nil
        default:
            return false
        }
    }

    private struct MaterializedSource {
        let url: URL
        let cleanupAfterRun: Bool
    }

    @MainActor
    private static func materializedSource(for document: TextDocument) async throws -> MaterializedSource {
        if !document.isDirty, let url = document.fileURL {
            return MaterializedSource(url: url, cleanupAfterRun: false)
        }

        let ext = document.language.preferredExtension
        let directory = sourceDirectory(for: document)
        let url = directory.appendingPathComponent(".briskedit-run-\(UUID().uuidString).\(ext)")
        let text = document.text
        try await Task.detached(priority: .userInitiated) {
            try text.write(to: url, atomically: true, encoding: .utf8)
        }.value
        return MaterializedSource(url: url, cleanupAfterRun: true)
    }

    @MainActor
    private static func sourceDirectory(for document: TextDocument) -> URL {
        switch document.language {
        case .c, .cpp:
            return document.fileURL?.deletingLastPathComponent() ?? FileManager.default.temporaryDirectory
        default:
            return FileManager.default.temporaryDirectory
        }
    }

    private static func runDirectory(for sourceURL: URL, workspaceRoot: URL?) -> URL {
        workspaceRoot ?? sourceURL.deletingLastPathComponent()
    }

    private static func ancestor(containing filename: String, from start: URL, stopAt: URL?) -> URL? {
        var current = start
        let fm = FileManager.default
        while true {
            if fm.fileExists(atPath: current.appendingPathComponent(filename).path) {
                return current
            }
            if let stopAt, current.standardizedFileURL == stopAt.standardizedFileURL {
                return nil
            }
            let parent = current.deletingLastPathComponent()
            if parent.path == current.path { return nil }
            current = parent
        }
    }

    private static func tempBinaryPath() -> String {
        "/tmp/briskedit-\(UUID().uuidString)"
    }

    static func shellQuote(_ value: String) -> String {
        "'\(value.replacingOccurrences(of: "'", with: "'\\''"))'"
    }
}

enum RunError: LocalizedError {
    case noDocument
    case unsupported(String)
    case needsSavedProjectFile(String)

    var errorDescription: String? {
        switch self {
        case .noDocument:
            "No active document to run."
        case .unsupported(let language):
            "Running \(language) files is not supported yet."
        case .needsSavedProjectFile(let name):
            "Save \(name) before running this project."
        }
    }
}
