import Foundation
import OSLog

actor FormatterRequestGate {
    private var isActive = false
    private var suppressedRequests = 0

    func begin() -> Bool {
        guard !isActive else {
            suppressedRequests += 1
            return false
        }
        isActive = true
        return true
    }

    func finish() -> Int {
        isActive = false
        defer { suppressedRequests = 0 }
        return suppressedRequests
    }
}

/// Runs an external code formatter over a buffer *only if the tool is already
/// installed* — in the spirit of "use the tools you already have". It never
/// installs anything and returns `nil` whenever no formatter applies, the tool
/// is missing, or formatting fails, so the caller saves the original text.
///
/// Formatters are invoked through a login shell (`zsh -lc`) so a GUI launch
/// still sees Homebrew/`PATH` entries, mirroring how `Run` resolves toolchains.
enum FormatterService {
    private static let requestGate = FormatterRequestGate()
    private static let maximumConfigSearchDepth = 128
    private static let formatterTimeout: TimeInterval = 15
    private static let maximumInputBytes = 16 * 1024 * 1024
    private static let maximumOutputBytes = 32 * 1024 * 1024
    private static let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "com.johannesgrof.briskedit",
        category: "Formatter"
    )

    /// `indentWidth` is the editor's configured indentation, used as a fallback
    /// for formatters that take an explicit width when no project config file is
    /// present (so the result matches the editor instead of the tool's default).
    static func format(text: String, language: SourceLanguage, fileURL: URL?, indentWidth: Int = 4) async -> String? {
        guard await requestGate.begin() else { return nil }
        let startedAt = Date()
        let inputBytes = text.utf8.count
        guard inputBytes <= maximumInputBytes else {
            _ = await requestGate.finish()
            logger.error("Formatter rejected \(inputBytes, privacy: .public)-byte input")
            return nil
        }
        logger.info("Formatter started for \(language.rawValue, privacy: .public), input bytes: \(inputBytes, privacy: .public)")

        let result = await Task.detached(priority: .userInitiated) { () -> String? in
            guard let executable = executable(for: language),
                  let command = command(for: language, fileURL: fileURL, indentWidth: indentWidth) else { return nil }
            // Run in the file's own directory so tools discover project config
            // exactly as they do from the command line. Command construction may
            // walk the file hierarchy, so it belongs off the main actor too.
            let workingDirectory = fileURL?.deletingLastPathComponent()
            return run(command: command, executable: executable, input: text, workingDirectory: workingDirectory)
        }.value

        let suppressedRequests = await requestGate.finish()
        let duration = Date().timeIntervalSince(startedAt)
        logger.info("Formatter finished for \(language.rawValue, privacy: .public), duration: \(duration, privacy: .public), suppressed requests: \(suppressedRequests)")
        return result
    }

    /// Whether a `.clang-format` (or `_clang-format`) exists at `dir` or any
    /// ancestor — i.e. clang-format's `-style=file` would find a real config.
    static func hasClangFormatConfig(startingFrom dir: URL) -> Bool {
        guard dir.isFileURL else { return false }
        let fm = FileManager.default
        var currentPath = dir.standardizedFileURL.path
        var visitedPaths = Set<String>()

        for _ in 0..<maximumConfigSearchDepth {
            guard !currentPath.isEmpty, visitedPaths.insert(currentPath).inserted else { return false }
            let path = currentPath as NSString
            if fm.fileExists(atPath: path.appendingPathComponent(".clang-format")) ||
               fm.fileExists(atPath: path.appendingPathComponent("_clang-format")) {
                return true
            }
            let parentPath = path.deletingLastPathComponent
            guard !parentPath.isEmpty, parentPath != currentPath else { return false }
            currentPath = parentPath
        }
        return false
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
        let data = Data(input.utf8)
        let directory = workingDirectory.flatMap {
            FileManager.default.fileExists(atPath: $0.path) ? $0 : nil
        }
        guard let result = BoundedProcessRunner.run(
            executableURL: URL(fileURLWithPath: "/bin/zsh"),
            arguments: ["-lc", "command -v \(executable) >/dev/null 2>&1 || exit 127\nexec \(command)"],
            currentDirectoryURL: directory,
            input: data,
            timeout: formatterTimeout,
            maximumStandardOutputBytes: maximumOutputBytes,
            maximumStandardErrorBytes: 256 * 1024
        ) else { return nil }
        if result.timedOut {
            logger.error("Formatter exceeded \(formatterTimeout, privacy: .public) seconds and was terminated")
        }
        if result.outputLimitExceeded {
            logger.error("Formatter exceeded its output limit and was discarded")
        }
        guard !result.timedOut,
              !result.outputLimitExceeded,
              result.terminationStatus == 0,
              let formatted = String(data: result.stdout, encoding: .utf8),
              !formatted.isEmpty else { return nil }
        return formatted
    }
}
