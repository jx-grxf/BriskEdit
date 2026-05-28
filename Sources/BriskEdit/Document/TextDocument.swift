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
    private var lineStartOffsets: [Int] = [0]

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
        rebuildLineIndex()
        isDirty = true
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
    case python = "Python"
    case rust = "Rust"
    case shell = "Shell"
    case swift = "Swift"
    case typescript = "TypeScript"
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
        case "py": self = .python
        case "rs": self = .rust
        case "sh", "bash", "zsh": self = .shell
        case "swift": self = .swift
        case "ts", "tsx": self = .typescript
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
        case .python: "chevron.left.forwardslash.chevron.right"
        case .rust: "gearshape.2"
        case .shell: "terminal"
        case .swift: "swift"
        case .typescript: "t.square"
        case .yaml: "list.bullet.rectangle"
        case .plainText: "doc.text"
        }
    }

    var isRunnable: Bool {
        switch self {
        case .c, .cpp, .go, .javascript, .python, .rust, .shell, .swift, .typescript:
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
        case .yaml: "yml"
        case .plainText: "txt"
        }
    }
}
