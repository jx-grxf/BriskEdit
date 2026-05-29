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
    let severity: Severity
    let message: String

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
        guard let spec = spec(for: language) else { return nil }
        return await Task.detached(priority: .utility) { () -> [Diagnostic]? in
            // Stage the (possibly unsaved) buffer in a sibling temp file so the
            // user's real file is never touched, while relative `#include`s still
            // resolve against the project directory. Falls back to the temp dir
            // for untitled buffers.
            let directory = fileURL?.deletingLastPathComponent() ?? FileManager.default.temporaryDirectory
            let staged = directory.appendingPathComponent("brisk-check-\(UUID().uuidString).\(language.preferredExtension)")
            guard (try? text.write(to: staged, atomically: true, encoding: .utf8)) != nil else { return nil }
            defer { try? FileManager.default.removeItem(at: staged) }

            let command = spec.command(staged.path, directory.path)
            guard let output = runCapturingStderr(command) else { return nil }
            return parse(output, filename: staged.lastPathComponent)
        }.value
    }

    private struct Spec {
        let command: (_ file: String, _ dir: String) -> String
    }

    private static func spec(for language: SourceLanguage) -> Spec? {
        let q = RunService.shellQuote
        switch language {
        case .c:
            return Spec { file, dir in
                "xcrun clang -fsyntax-only -fno-color-diagnostics -Wall -DprintDih=printf -I \(q(dir)) \(q(file))"
            }
        case .cpp:
            return Spec { file, dir in
                "xcrun clang++ -std=c++20 -fsyntax-only -fno-color-diagnostics -Wall -I \(q(dir)) \(q(file))"
            }
        case .swift:
            return Spec { file, _ in
                "xcrun swiftc -typecheck -no-color-diagnostics \(q(file))"
            }
        default:
            return nil
        }
    }

    /// Matches the clang/swiftc shared format: `path:line:col: severity: message`.
    private static let lineRegex = try? NSRegularExpression(
        pattern: #"^(.*?):(\d+):(\d+): (error|warning|note): (.*)$"#,
        options: [.anchorsMatchLines]
    )

    private static func parse(_ output: String, filename: String) -> [Diagnostic] {
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
            diagnostics.append(Diagnostic(line: line, column: col, severity: severity, message: group(5)))
        }
        return diagnostics
    }

    private static func runCapturingStderr(_ command: String) -> String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/zsh")
        process.arguments = ["-lc", command]
        let stdout = Pipe()
        let stderr = Pipe()
        process.standardOutput = stdout
        process.standardError = stderr
        do { try process.run() } catch { return nil }
        let errData = stderr.fileHandleForReading.readDataToEndOfFile()
        _ = stdout.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return String(data: errData, encoding: .utf8)
    }
}
