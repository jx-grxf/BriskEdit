import Foundation

/// Runs an external code formatter over a buffer *only if the tool is already
/// installed* — in the spirit of "use the tools you already have". It never
/// installs anything and returns `nil` whenever no formatter applies, the tool
/// is missing, or formatting fails, so the caller saves the original text.
///
/// Formatters are invoked through a login shell (`zsh -lc`) so a GUI launch
/// still sees Homebrew/`PATH` entries, mirroring how `Run` resolves toolchains.
enum FormatterService {
    /// `indentWidth` is the editor's configured indentation, used as a fallback
    /// for formatters that take an explicit width when no project config file is
    /// present (so the result matches the editor instead of the tool's default).
    static func format(text: String, language: SourceLanguage, fileURL: URL?, indentWidth: Int = 4) async -> String? {
        return await Task.detached(priority: .userInitiated) { () -> String? in
            guard let executable = executable(for: language),
                  let command = command(for: language, fileURL: fileURL, indentWidth: indentWidth) else { return nil }
            // Run in the file's own directory so tools discover project config
            // exactly as they do from the command line. Command construction may
            // walk the file hierarchy, so it belongs off the main actor too.
            let workingDirectory = fileURL?.deletingLastPathComponent()
            return run(command: command, executable: executable, input: text, workingDirectory: workingDirectory)
        }.value
    }

    /// Whether a `.clang-format` (or `_clang-format`) exists at `dir` or any
    /// ancestor — i.e. clang-format's `-style=file` would find a real config.
    private static func hasClangFormatConfig(startingFrom dir: URL) -> Bool {
        let fm = FileManager.default
        var current = dir.standardizedFileURL
        while true {
            if fm.fileExists(atPath: current.appendingPathComponent(".clang-format").path) ||
               fm.fileExists(atPath: current.appendingPathComponent("_clang-format").path) {
                return true
            }
            let parent = current.deletingLastPathComponent()
            if parent.path == current.path { return false }
            current = parent
        }
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
    /// The *full* path (not just the name) is handed to the path-aware tools so
    /// they locate the project's config relative to the real file location.
    private static func command(for language: SourceLanguage, fileURL: URL?, indentWidth: Int) -> String? {
        let fullPath = fileURL.map { RunService.shellQuote($0.path) }
        switch language {
        case .c, .cpp:
            let assume = fullPath.map { " -assume-filename=\($0)" } ?? ""
            // A project `.clang-format` wins (`-style=file`); otherwise format with
            // an inline LLVM style carrying the editor's indent width, so output
            // respects either the repo's rules or the user's setting — not the
            // tool's hard-coded 2-space default. (`-fallback-style` only accepts
            // *named* styles, so an inline fallback would make clang-format error
            // out and silently produce no change — the inline goes on `-style`.)
            let hasProjectStyle = fileURL.map {
                Self.hasClangFormatConfig(startingFrom: $0.deletingLastPathComponent())
            } ?? false
            let style = hasProjectStyle
                ? "-style=file -fallback-style=LLVM"
                : "-style=\"{BasedOnStyle: LLVM, IndentWidth: \(indentWidth), TabWidth: \(indentWidth)}\""
            return "clang-format \(style)\(assume)"
        case .swift:
            return "swift-format format"
        case .go:
            return "gofmt"
        case .rust:
            return "rustfmt --emit stdout 2>/dev/null"
        case .python:
            return "black -q -"
        case .javascript, .typescript, .css, .json, .html, .markdown, .yaml:
            let fp = fullPath ?? RunService.shellQuote("file.\(language.preferredExtension)")
            return "prettier --stdin-filepath \(fp)"
        default:
            return nil
        }
    }

    /// Runs `zsh -lc`, feeding `input` on stdin (written off-thread to avoid a
    /// pipe-buffer deadlock) and returning stdout only on a clean exit.
    private static func run(command: String, executable: String, input: String, workingDirectory: URL? = nil) -> String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/zsh")
        process.arguments = ["-lc", "command -v \(executable) >/dev/null 2>&1 || exit 127\n\(command)"]
        if let workingDirectory, FileManager.default.fileExists(atPath: workingDirectory.path) {
            process.currentDirectoryURL = workingDirectory
        }

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
