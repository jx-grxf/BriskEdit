import Foundation
import Observation

@MainActor
@Observable
final class TextDocument {
    private(set) var fileURL: URL?
    private(set) var encoding: String.Encoding
    var text: String
    var isDirty: Bool = false
    var cursorLine: Int = 1
    var cursorColumn: Int = 1
    /// Set when the file changed on disk while this buffer still had unsaved
    /// edits — the UI offers a reload instead of silently dropping either side.
    var externalChangePending: Bool = false
    /// Latest compiler/LSP findings, shown as gutter markers.
    var diagnostics: [Diagnostic] = []
    /// Bumped on every text mutation so the editor can detect *external* changes
    /// cheaply, instead of comparing entire (possibly huge) strings each update.
    private(set) var revision: Int = 0
    private var lineStartOffsets: [Int] = [0]
    private var lineIndexWork: DispatchWorkItem?

    var displayName: String {
        fileURL?.lastPathComponent ?? "Untitled"
    }

    var language: SourceLanguage {
        SourceLanguage(url: fileURL, displayName: displayName)
    }

    var fileSizeLabel: String {
        ByteCountFormatter.string(fromByteCount: Int64(text.utf8.count), countStyle: .file)
    }

    init(fileURL: URL?, text: String, encoding: String.Encoding) {
        self.fileURL = fileURL
        self.text = text
        self.encoding = encoding
        rebuildLineIndex()
    }

    static func empty() -> TextDocument {
        TextDocument(fileURL: nil, text: "", encoding: .utf8)
    }

    static func load(from url: URL) async throws -> TextDocument {
        let loaded = try await Task.detached(priority: .userInitiated) { () -> (String, String.Encoding) in
            var used: String.Encoding = .utf8
            let str = try String(contentsOf: url, usedEncoding: &used)
            return (str, used)
        }.value
        return TextDocument(fileURL: url, text: loaded.0, encoding: loaded.1)
    }

    func applyEdit(text newText: String) {
        guard text != newText else { return }
        text = newText
        revision &+= 1
        isDirty = true
        scheduleLineIndexRebuild()
    }

    /// Small files rebuild the line index immediately (exact Ln/Col); large files
    /// debounce it so typing in a 20 MB file stays smooth.
    private func scheduleLineIndexRebuild() {
        lineIndexWork?.cancel()
        if (text as NSString).length <= 100_000 {
            rebuildLineIndex()
            return
        }
        let work = DispatchWorkItem { [weak self] in self?.rebuildLineIndex() }
        lineIndexWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2, execute: work)
    }

    /// Points the document at a new on-disk location (e.g. after a rename)
    /// without touching the buffer or dirty state.
    func retarget(to url: URL) {
        fileURL = url
    }

    /// Replaces the buffer with formatter output just before a save. Bumps
    /// `revision` so the editor re-seeds; the following save clears dirty state.
    func applyFormatted(_ newText: String) {
        guard newText != text else { return }
        text = newText
        revision &+= 1
        rebuildLineIndex()
    }

    /// Re-reads the file from disk after an external change. Bumps `revision`
    /// so the editor re-seeds its text view, and clears dirty/pending state.
    func reloadFromDisk() async {
        guard let url = fileURL else { return }
        let loaded = try? await Task.detached(priority: .userInitiated) { () -> (String, String.Encoding) in
            var used: String.Encoding = .utf8
            let str = try String(contentsOf: url, usedEncoding: &used)
            return (str, used)
        }.value
        guard let loaded else { return }
        text = loaded.0
        encoding = loaded.1
        revision &+= 1
        isDirty = false
        externalChangePending = false
        rebuildLineIndex()
    }

    func updateCursor(location: Int) {
        let safeLocation = max(0, min(location, text.utf16.count))
        var low = 0
        var high = lineStartOffsets.count
        while low < high {
            let mid = (low + high) / 2
            if lineStartOffsets[mid] <= safeLocation {
                low = mid + 1
            } else {
                high = mid
            }
        }
        let lineIndex = max(0, low - 1)
        cursorLine = lineIndex + 1
        cursorColumn = safeLocation - lineStartOffsets[lineIndex] + 1
    }

    func save() async throws {
        guard let url = fileURL else { throw CocoaError(.fileWriteUnknown) }
        try await write(to: url, encoding: encoding)
        isDirty = false
    }

    func save(to url: URL) async throws {
        try await write(to: url, encoding: encoding)
        fileURL = url
        isDirty = false
    }

    private func write(to url: URL, encoding: String.Encoding) async throws {
        let snapshot = text
        try await Task.detached(priority: .userInitiated) { [snapshot, encoding] in
            try snapshot.write(to: url, atomically: true, encoding: encoding)
        }.value
    }

    private func rebuildLineIndex() {
        var starts = [0]
        let nsString = text as NSString
        nsString.enumerateSubstrings(
            in: NSRange(location: 0, length: nsString.length),
            options: [.byLines, .substringNotRequired]
        ) { _, _, enclosingRange, _ in
            let next = NSMaxRange(enclosingRange)
            if next < nsString.length {
                starts.append(next)
            }
        }
        lineStartOffsets = starts
    }
}

enum SourceLanguage: String, Sendable, CaseIterable {
    case c = "C"
    case cpp = "C++"
    case css = "CSS"
    case go = "Go"
    case html = "HTML"
    case javascript = "JavaScript"
    case json = "JSON"
    case markdown = "Markdown"
    case php = "PHP"
    case python = "Python"
    case rust = "Rust"
    case shell = "Shell"
    case swift = "Swift"
    case typescript = "TypeScript"
    case xml = "XML"
    case yaml = "YAML"
    case plainText = "Plain Text"

    init(url: URL?, displayName: String) {
        let ext = (url?.pathExtension.isEmpty == false ? url?.pathExtension : (displayName as NSString).pathExtension)?.lowercased() ?? ""
        switch ext {
        case "c", "h": self = .c
        case "cc", "cpp", "cxx", "hpp", "hh": self = .cpp
        case "css": self = .css
        case "go": self = .go
        case "htm", "html": self = .html
        case "js", "jsx", "mjs", "cjs": self = .javascript
        case "json": self = .json
        case "md", "markdown": self = .markdown
        case "php": self = .php
        case "py": self = .python
        case "rs": self = .rust
        case "sh", "bash", "zsh": self = .shell
        case "swift": self = .swift
        case "ts", "tsx": self = .typescript
        case "xml", "plist", "xib", "storyboard": self = .xml
        case "yaml", "yml": self = .yaml
        default: self = .plainText
        }
    }

    var iconName: String {
        switch self {
        case .c: "c.circle"
        case .cpp: "plus.forwardslash.minus"
        case .css: "paintbrush"
        case .go: "bolt.horizontal"
        case .html: "globe"
        case .javascript: "curlybraces"
        case .json: "curlybraces.square"
        case .markdown: "doc.richtext"
        case .php: "p.square"
        case .python: "chevron.left.forwardslash.chevron.right"
        case .rust: "gearshape.2"
        case .shell: "terminal"
        case .swift: "swift"
        case .typescript: "t.square"
        case .xml: "chevron.left.forwardslash.chevron.right"
        case .yaml: "list.bullet.rectangle"
        case .plainText: "doc.text"
        }
    }

    var isRunnable: Bool {
        switch self {
        case .c, .cpp, .go, .javascript, .php, .python, .rust, .shell, .swift, .typescript:
            true
        default:
            false
        }
    }

    var preferredExtension: String {
        switch self {
        case .c: "c"
        case .cpp: "cpp"
        case .go: "go"
        case .javascript: "js"
        case .python: "py"
        case .rust: "rs"
        case .shell: "sh"
        case .swift: "swift"
        case .typescript: "ts"
        case .css: "css"
        case .html: "html"
        case .json: "json"
        case .markdown: "md"
        case .php: "php"
        case .yaml: "yml"
        case .xml: "xml"
        case .plainText: "txt"
        }
    }

    var completionWords: [String] {
        switch self {
        case .c:
            ["#include", "#define", "printDih", "printf", "scanf", "malloc", "free", "sizeof", "int", "char", "double", "float", "void", "struct", "return", "for", "while", "if", "else"]
        case .cpp:
            ["#include", "std::cout", "std::cin", "std::vector", "std::string", "namespace", "class", "template", "typename", "auto", "const", "return", "for", "while", "if", "else"]
        case .swift:
            ["import", "struct", "class", "enum", "extension", "func", "var", "let", "guard", "if", "else", "switch", "case", "return", "async", "await"]
        case .javascript, .typescript:
            ["import", "export", "const", "let", "function", "async", "await", "return", "class", "interface", "type", "if", "else", "for", "while"]
        case .python:
            ["import", "from", "def", "class", "self", "return", "if", "elif", "else", "for", "while", "with", "try", "except"]
        case .go:
            ["package", "import", "func", "return", "struct", "interface", "defer", "go", "range", "if", "else", "for"]
        case .rust:
            ["use", "fn", "let", "mut", "pub", "impl", "trait", "struct", "enum", "match", "return", "async", "await"]
        case .shell:
            ["#!/usr/bin/env bash", "set -euo pipefail", "if", "then", "else", "fi", "for", "do", "done", "case", "esac"]
        case .html, .xml:
            ["html", "head", "body", "script", "style", "div", "span", "section", "article", "link", "meta"]
        case .css:
            ["display", "grid", "flex", "align-items", "justify-content", "color", "background", "font-size", "padding", "margin"]
        case .json, .yaml, .markdown, .php, .plainText:
            []
        }
    }
}
