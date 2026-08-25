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

        if document.language == .java {
            let javaSource = try await materializedJavaSource(for: document)
            let sourceFile = shellQuote(javaSource.sourceURL.path)
            let classes = shellQuote(javaSource.classOutputURL.path)
            let cleanupDirectory = shellQuote(javaSource.cleanupDirectory.path)
            let mainClass = shellQuote(javaSource.mainClass)
            let line = "(__brisk_javac=''; __brisk_java=''; if /usr/libexec/java_home >/dev/null 2>&1; then __brisk_jhome=$(/usr/libexec/java_home); __brisk_javac=\"$__brisk_jhome/bin/javac\"; __brisk_java=\"$__brisk_jhome/bin/java\"; elif command -v javac >/dev/null 2>&1 && command -v java >/dev/null 2>&1 && javac -version >/dev/null 2>&1 && java -version >/dev/null 2>&1; then __brisk_javac='javac'; __brisk_java='java'; elif command -v brew >/dev/null 2>&1 && __brisk_jhome=$(brew --prefix openjdk 2>/dev/null) && [ -x \"$__brisk_jhome/bin/javac\" ] && [ -x \"$__brisk_jhome/bin/java\" ]; then __brisk_javac=\"$__brisk_jhome/bin/javac\"; __brisk_java=\"$__brisk_jhome/bin/java\"; fi; if [ -z \"$__brisk_javac\" ]; then echo 'BriskEdit: install a JDK to run Java files.'; false; else \"$__brisk_javac\" -d \(classes) \(sourceFile) && \"$__brisk_java\" -cp \(classes) \(mainClass); fi); __brisk_status=$?; rm -rf \(cleanupDirectory); printf '\\n[exit %s]\\n' \"$__brisk_status\""
            return RunCommand(title: "Run \(document.displayName)", shellLine: line, cwd: runDirectory(for: javaSource.sourceURL, workspaceRoot: workspaceRoot))
        }

        let source = try await materializedSource(for: document)
        let sourceURL = source.url
        let cwd = runDirectory(for: source.includeDirectory ?? sourceURL, workspaceRoot: workspaceRoot)
        let file = shellQuote(sourceURL.path)
        let cleanup = source.cleanupAfterRun ? " ; rm -f \(file)" : ""
        // Staged buffers live in the temp directory, so quoted includes and
        // sibling imports need the original file's directory handed back.
        let includeFlag = source.includeDirectory.map { " -I \(shellQuote($0.path))" } ?? ""

        let line: String
        switch document.language {
        case .c:
            let output = shellQuote(tempBinaryPath())
            // Prefer the `cc` stub (and `xcrun clang`) over a raw toolchain path:
            // both set up the SDK sysroot so system headers (stdio.h…) resolve.
            // Invoking `xcrun --find clang`'s result directly skips that and fails.
            let extra = SecretMode.isEnabled ? " -DprintDih=printf" : ""
            line = "(if command -v cc >/dev/null 2>&1; then __cc='cc'; elif xcrun --find clang >/dev/null 2>&1; then __cc='xcrun clang'; elif command -v gcc >/dev/null 2>&1; then __cc='gcc'; else __cc=''; fi; if [ -z \"$__cc\" ]; then echo 'BriskEdit: install clang or gcc to run C files.'; false; else $__cc \(file)\(includeFlag) -Wall -Wextra\(extra) -o \(output) && \(output); fi); __brisk_status=$?; rm -f \(output)\(cleanup); printf '\\n[exit %s]\\n' \"$__brisk_status\""
        case .cpp:
            let output = shellQuote(tempBinaryPath())
            line = "(if command -v c++ >/dev/null 2>&1; then __cxx='c++'; elif xcrun --find clang++ >/dev/null 2>&1; then __cxx='xcrun clang++'; elif command -v g++ >/dev/null 2>&1; then __cxx='g++'; else __cxx=''; fi; if [ -z \"$__cxx\" ]; then echo 'BriskEdit: install clang++ or g++ to run C++ files.'; false; else $__cxx \(file)\(includeFlag) -Wall -Wextra -std=c++20 -o \(output) && \(output); fi); __brisk_status=$?; rm -f \(output)\(cleanup); printf '\\n[exit %s]\\n' \"$__brisk_status\""
        case .swift:
            if let packageRoot = ancestor(containing: "Package.swift", from: sourceURL.deletingLastPathComponent(), stopAt: workspaceRoot) {
                return RunCommand(title: "swift run", shellLine: "swift run", cwd: packageRoot)
            }
            line = "swift \(file)\(cleanup)"
        case .python:
            let pythonPath = source.includeDirectory.map { "PYTHONPATH=\(shellQuote($0.path)) " } ?? ""
            line = "\(pythonPath)python3 \(file)\(cleanup)"
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
            if let moduleRoot = ancestor(containing: "go.mod", from: sourceURL.deletingLastPathComponent(), stopAt: workspaceRoot) {
                return RunCommand(title: "go run", shellLine: "go run .", cwd: moduleRoot)
            }
            line = "go run \(file)\(cleanup)"
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
        /// Original directory of a staged (dirty) buffer, so include/import
        /// resolution and the fallback run directory stay in the project.
        var includeDirectory: URL? = nil
    }

    private struct MaterializedJavaSource {
        let sourceURL: URL
        let classOutputURL: URL
        let cleanupDirectory: URL
        let mainClass: String
    }

    @MainActor
    private static func materializedSource(for document: TextDocument) async throws -> MaterializedSource {
        if !document.isDirty, let url = document.fileURL {
            return MaterializedSource(url: url, cleanupAfterRun: false)
        }

        let ext = document.language.preferredExtension
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(".briskedit-run-\(UUID().uuidString).\(ext)")
        let text = document.text
        try await Task.detached(priority: .userInitiated) {
            try text.write(to: url, atomically: true, encoding: .utf8)
        }.value
        return MaterializedSource(
            url: url,
            cleanupAfterRun: true,
            includeDirectory: document.fileURL?.deletingLastPathComponent()
        )
    }

    @MainActor
    private static func materializedJavaSource(for document: TextDocument) async throws -> MaterializedJavaSource {
        let text = document.text
        let fallbackName = document.fileURL?.deletingPathExtension().lastPathComponent ?? "Main"
        let typeName = javaPrimaryTypeName(in: text) ?? javaSafeTypeName(fallbackName)
        let packageName = javaPackageName(in: text)
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("briskedit-java-\(UUID().uuidString)", isDirectory: true)
        let sourceURL = root.appendingPathComponent("\(typeName).java")
        let classOutputURL = root.appendingPathComponent("classes", isDirectory: true)
        try FileManager.default.createDirectory(at: classOutputURL, withIntermediateDirectories: true)
        try await Task.detached(priority: .userInitiated) {
            try text.write(to: sourceURL, atomically: true, encoding: .utf8)
        }.value
        let mainClass = packageName.map { "\($0).\(typeName)" } ?? typeName
        return MaterializedJavaSource(sourceURL: sourceURL, classOutputURL: classOutputURL, cleanupDirectory: root, mainClass: mainClass)
    }

    private static func runDirectory(for sourceURL: URL, workspaceRoot: URL?) -> URL {
        workspaceRoot ?? sourceURL.deletingLastPathComponent()
    }

    private static func ancestor(containing filename: String, from start: URL, stopAt: URL?) -> URL? {
        guard start.isFileURL else { return nil }
        let fm = FileManager.default
        var currentPath = start.standardizedFileURL.path
        let stopPath = stopAt?.standardizedFileURL.path
        var visitedPaths = Set<String>()
        for _ in 0..<128 {
            guard !currentPath.isEmpty, visitedPaths.insert(currentPath).inserted else { return nil }
            let path = currentPath as NSString
            if fm.fileExists(atPath: path.appendingPathComponent(filename)) {
                return URL(fileURLWithPath: currentPath, isDirectory: true)
            }
            if currentPath == stopPath { return nil }
            let parentPath = path.deletingLastPathComponent
            guard !parentPath.isEmpty, parentPath != currentPath else { return nil }
            currentPath = parentPath
        }
        return nil
    }

    private static func tempBinaryPath() -> String {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("briskedit-\(UUID().uuidString)").path
    }

    private static func javaPrimaryTypeName(in text: String) -> String? {
        javaFirstMatch(in: text, pattern: #"(?m)^\s*public\s+(?:final\s+|abstract\s+|sealed\s+|non-sealed\s+)*(?:class|interface|enum|record)\s+([A-Za-z_$][A-Za-z0-9_$]*)"#)
            ?? javaFirstMatch(in: text, pattern: #"(?m)^\s*(?:final\s+|abstract\s+|sealed\s+|non-sealed\s+)*(?:class|interface|enum|record)\s+([A-Za-z_$][A-Za-z0-9_$]*)"#)
    }

    private static func javaPackageName(in text: String) -> String? {
        javaFirstMatch(in: text, pattern: #"(?m)^\s*package\s+([A-Za-z_$][A-Za-z0-9_$]*(?:\.[A-Za-z_$][A-Za-z0-9_$]*)*)\s*;"#)
    }

    private static func javaFirstMatch(in text: String, pattern: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
        let ns = text as NSString
        let range = NSRange(location: 0, length: ns.length)
        guard let match = regex.firstMatch(in: text, range: range), match.numberOfRanges > 1 else { return nil }
        return ns.substring(with: match.range(at: 1))
    }

    private static func javaSafeTypeName(_ value: String) -> String {
        let allowed = value.filter { $0.isLetter || $0.isNumber || $0 == "_" || $0 == "$" }
        guard let first = allowed.first, first.isLetter || first == "_" || first == "$" else { return "Main" }
        return allowed.isEmpty ? "Main" : allowed
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
