import Foundation

/// Runs an external code formatter over a buffer *only if the tool is already
/// installed* — in the spirit of "use the tools you already have". It never
/// installs anything and returns `nil` whenever no formatter applies, the tool
/// is missing, or formatting fails, so the caller saves the original text.
///
/// Formatters are invoked through a login shell (`zsh -lc`) so a GUI launch
/// still sees Homebrew/`PATH` entries, mirroring how `Run` resolves toolchains.
enum FormatterService {
    static func format(text: String, language: SourceLanguage, fileURL: URL?) async -> String? {
        guard let command = command(for: language, fileURL: fileURL) else { return nil }
        return await Task.detached(priority: .userInitiated) { () -> String? in
            run(command: command, executable: executable(for: language)!, input: text)
        }.value
    }

    /// The bare executable name, used for an `command -v` availability probe.
    private static func executable(for language: SourceLanguage) -> String? {
        switch language {
        case .c, .cpp: "clang-format"
        case .swift: "swift-format"
        case .go: "gofmt"
        case .rust: "rustfmt"
        case .python: "black"
        case .javascript, .typescript, .css, .json, .html, .markdown, .yaml: "prettier"
        default: nil
        }
    }

    /// The full shell command piped stdin → stdout for each language's formatter.
    private static func command(for language: SourceLanguage, fileURL: URL?) -> String? {
        let filename = fileURL.map { RunService.shellQuote($0.lastPathComponent) }
        switch language {
        case .c, .cpp:
            let assume = filename.map { " -assume-filename=\($0)" } ?? ""
            return "clang-format\(assume)"
        case .swift:
            return "swift-format format"
        case .go:
            return "gofmt"
        case .rust:
            return "rustfmt --emit stdout 2>/dev/null"
        case .python:
            return "black -q -"
        case .javascript, .typescript, .css, .json, .html, .markdown, .yaml:
            let fp = filename ?? RunService.shellQuote("file.\(language.preferredExtension)")
            return "prettier --stdin-filepath \(fp)"
        default:
            return nil
        }
    }

    /// Runs `zsh -lc`, feeding `input` on stdin (written off-thread to avoid a
    /// pipe-buffer deadlock) and returning stdout only on a clean exit.
    private static func run(command: String, executable: String, input: String) -> String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/zsh")
        process.arguments = ["-lc", "command -v \(executable) >/dev/null 2>&1 || exit 127\n\(command)"]

        let stdin = Pipe()
        let stdout = Pipe()
        let stderr = Pipe()
        process.standardInput = stdin
        process.standardOutput = stdout
        process.standardError = stderr

        do { try process.run() } catch { return nil }

        let data = Data(input.utf8)
        DispatchQueue.global(qos: .userInitiated).async {
            stdin.fileHandleForWriting.write(data)
            try? stdin.fileHandleForWriting.close()
        }
        let outData = stdout.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()

        guard process.terminationStatus == 0,
              let formatted = String(data: outData, encoding: .utf8),
              !formatted.isEmpty else { return nil }
        return formatted
    }
}
