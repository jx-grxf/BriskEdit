import Foundation

/// A single compiler/linter finding, mapped to 1-based line/column in the buffer.
struct Diagnostic: Sendable, Hashable, Identifiable {
    enum Severity: Sendable, Hashable {
        case error
        case warning
        case note
    }

    let line: Int
    let column: Int
    /// End of the finding's range (1-based, exclusive column), when the source
    /// provides one — LSP carries a real range, the single-file clang/swiftc
    /// fallback only a point. `nil` means "underline the token at the start".
    var endLine: Int? = nil
    var endColumn: Int? = nil
    let severity: Severity
    let message: String
    /// Server/tool that produced the finding (e.g. "clang", "swiftc"), shown in
    /// the hover as a `C/C++(165)` source tag. Optional.
    var source: String? = nil

    var id: String { "\(line):\(column):\(severity):\(message)" }
}

/// Runs a fast syntax/type check with the user's own toolchain and parses the
/// findings into `Diagnostic`s — the cheap, no-LSP way to surface "this won't
/// compile" right in the gutter. Returns nil for languages it doesn't drive.
///
/// Single-file checks have no project include/search paths, so cross-file
/// references can read as errors; the LSP client is the precise path. This is
/// the zero-config fallback that always works on a stock dev box.
enum DiagnosticsService {
    static func check(text: String, language: SourceLanguage, fileURL: URL?) async -> [Diagnostic]? {
        guard text.utf8.count <= 8 * 1024 * 1024 else { return nil }
        guard let spec = spec(for: language) else { return nil }
        return await Task.detached(priority: .utility) { () -> [Diagnostic]? in
            // Stage the (possibly unsaved) buffer in the per-user temp
            // directory so the user's real file and project directory are
            // never touched; `-I <original directory>` below keeps relative
            // `#include`s resolving against the project.
            let originalDirectory = fileURL?.deletingLastPathComponent()
            let staged = FileManager.default.temporaryDirectory
                .appendingPathComponent("brisk-check-\(UUID().uuidString).\(language.preferredExtension)")
            guard (try? text.write(to: staged, atomically: true, encoding: .utf8)) != nil else { return nil }
            defer { try? FileManager.default.removeItem(at: staged) }

            let command = spec.command(staged.path, originalDirectory?.path ?? staged.deletingLastPathComponent().path)
            guard let output = runCapturingStderr(command) else { return nil }
            return parse(output, filename: staged.lastPathComponent, source: spec.source)
        }.value
    }

    private struct Spec {
        let command: (_ file: String, _ dir: String) -> String
        let source: String
    }

    private static func spec(for language: SourceLanguage) -> Spec? {
        let q = RunService.shellQuote
        switch language {
        case .c:
            return Spec(command: { file, dir in
                // Match RunService: the easter-egg macro only exists when
                // secret mode is on, so diagnostics and runtime agree on
                // whether `printDih` is defined.
                let extra = SecretMode.isEnabled ? " -DprintDih=printf" : ""
                return "xcrun clang -fsyntax-only -fno-color-diagnostics -Wall\(extra) -I \(q(dir)) \(q(file))"
            }, source: "clang")
        case .cpp:
            return Spec(command: { file, dir in
                "xcrun clang++ -std=c++20 -fsyntax-only -fno-color-diagnostics -Wall -I \(q(dir)) \(q(file))"
            }, source: "clang")
        case .swift:
            return Spec(command: { file, _ in
                "xcrun swiftc -typecheck -no-color-diagnostics \(q(file))"
            }, source: "swiftc")
        default:
            return nil
        }
    }

    /// Matches the clang/swiftc shared format: `path:line:col: severity: message`.
    private static let lineRegex = try? NSRegularExpression(
        pattern: #"^(.*?):(\d+):(\d+): (error|warning|note): (.*)$"#,
        options: [.anchorsMatchLines]
    )

    private static func parse(_ output: String, filename: String, source: String) -> [Diagnostic] {
        guard let regex = lineRegex else { return [] }
        var diagnostics: [Diagnostic] = []
        regex.enumerateMatches(in: output, range: NSRange(output.startIndex..., in: output)) { match, _, _ in
            guard let match else { return }
            func group(_ i: Int) -> String {
                guard let r = Range(match.range(at: i), in: output) else { return "" }
                return String(output[r])
            }
            // Only keep findings for the file under check, not its headers.
            guard (group(1) as NSString).lastPathComponent == filename else { return }
            guard let line = Int(group(2)), let col = Int(group(3)) else { return }
            let severity: Diagnostic.Severity = switch group(4) {
            case "error": .error
            case "warning": .warning
            default: .note
            }
            diagnostics.append(Diagnostic(line: line, column: col, severity: severity, message: group(5), source: source))
        }
        return diagnostics
    }

    private static func runCapturingStderr(_ command: String) -> String? {
        guard let result = BoundedProcessRunner.run(
            executableURL: URL(fileURLWithPath: "/bin/zsh"),
            arguments: ["-lc", "exec \(command)"],
            timeout: 20,
            maximumStandardOutputBytes: 256 * 1024,
            maximumStandardErrorBytes: 4 * 1024 * 1024
        ), !result.timedOut, !result.outputLimitExceeded else { return nil }
        return String(data: result.stderr, encoding: .utf8)
    }
}
