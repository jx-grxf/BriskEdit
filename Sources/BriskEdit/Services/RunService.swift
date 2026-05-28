import Foundation

struct RunCommand: Sendable {
    let title: String
    let shellLine: String
    let cwd: URL
}

enum RunService {
    @MainActor
    static func resolve(document: TextDocument?, workspaceRoot: URL?) throws -> RunCommand {
        guard let document else { throw RunError.noDocument }
        guard document.language.isRunnable else { throw RunError.unsupported(document.language.rawValue) }

        let sourceURL = try materializedSourceURL(for: document)
        let cwd = runDirectory(for: sourceURL, workspaceRoot: workspaceRoot)
        let file = shellQuote(sourceURL.path)
        let cleanup = sourceURL.path.hasPrefix(tempSourcePrefix) ? " ; rm -f \(file)" : ""

        let line: String
        switch document.language {
        case .c:
            let output = shellQuote(tempBinaryPath())
            line = "(xcrun clang \(file) -Wall -Wextra -o \(output) && \(output)); status=$?; rm -f \(output)\(cleanup); printf '\\n[exit %s]\\n' \"$status\""
        case .cpp:
            let output = shellQuote(tempBinaryPath())
            line = "(xcrun clang++ \(file) -Wall -Wextra -std=c++20 -o \(output) && \(output)); status=$?; rm -f \(output)\(cleanup); printf '\\n[exit %s]\\n' \"$status\""
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
            line = "(rustc \(file) -o \(output) && \(output)); status=$?; rm -f \(output)\(cleanup); printf '\\n[exit %s]\\n' \"$status\""
        default:
            throw RunError.unsupported(document.language.rawValue)
        }

        return RunCommand(title: "Run \(document.displayName)", shellLine: line, cwd: cwd)
    }

    @MainActor
    private static func materializedSourceURL(for document: TextDocument) throws -> URL {
        if !document.isDirty, let url = document.fileURL {
            return url
        }

        let ext = document.language.preferredExtension
        let url = URL(fileURLWithPath: "\(tempSourcePrefix)\(UUID().uuidString).\(ext)")
        try document.text.write(to: url, atomically: true, encoding: .utf8)
        return url
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

    private static var tempSourcePrefix: String {
        "/tmp/briskedit-source-"
    }

    static func shellQuote(_ value: String) -> String {
        "'\(value.replacingOccurrences(of: "'", with: "'\\''"))'"
    }
}

enum RunError: LocalizedError {
    case noDocument
    case unsupported(String)

    var errorDescription: String? {
        switch self {
        case .noDocument:
            "No active document to run."
        case .unsupported(let language):
            "Running \(language) files is not supported yet."
        }
    }
}
