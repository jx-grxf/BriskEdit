import Foundation

/// A code-structure snippet à la VS Code. `body` uses `\t` for one indent
/// level, `\n` for newlines, `$1{text}` for the placeholder that gets selected
/// on insertion, and `$0` for the final caret position.
struct CodeSnippet: Equatable, Sendable {
    let trigger: String
    let detail: String
    let body: String
}

/// One row in the completion popup. A plain identifier has `snippet == nil`;
/// snippet rows carry the structure to expand.
struct CompletionItem: Equatable {
    let label: String
    let detail: String?
    let snippet: CodeSnippet?

    init(label: String, detail: String? = nil, snippet: CodeSnippet? = nil) {
        self.label = label
        self.detail = detail
        self.snippet = snippet
    }
}

enum SnippetLibrary {
    static func snippets(for language: SourceLanguage) -> [CodeSnippet] {
        switch language {
        case .c, .cpp:
            return c
        case .swift:
            return swift
        case .python:
            return python
        case .javascript, .typescript:
            return javascript
        case .go:
            return go
        case .rust:
            return rust
        default:
            return []
        }
    }

    private static let c: [CodeSnippet] = [
        CodeSnippet(trigger: "for", detail: "for loop", body: "for (int i = 0; i < $1{count}; i++) {\n\t$0\n}"),
        CodeSnippet(trigger: "forr", detail: "reverse for loop", body: "for (int i = $1{count} - 1; i >= 0; i--) {\n\t$0\n}"),
        CodeSnippet(trigger: "while", detail: "while loop", body: "while ($1{condition}) {\n\t$0\n}"),
        CodeSnippet(trigger: "do", detail: "do-while loop", body: "do {\n\t$0\n} while ($1{condition});"),
        CodeSnippet(trigger: "if", detail: "if statement", body: "if ($1{condition}) {\n\t$0\n}"),
        CodeSnippet(trigger: "ifelse", detail: "if-else", body: "if ($1{condition}) {\n\t$0\n} else {\n\t\n}"),
        CodeSnippet(trigger: "switch", detail: "switch", body: "switch ($1{value}) {\n\tcase $0:\n\t\tbreak;\n\tdefault:\n\t\tbreak;\n}"),
        CodeSnippet(trigger: "main", detail: "main function", body: "int main(int argc, char *argv[]) {\n\t$0\n\treturn 0;\n}"),
        CodeSnippet(trigger: "include", detail: "#include <…>", body: "#include <$1{stdio.h}>$0"),
        CodeSnippet(trigger: "define", detail: "#define", body: "#define $1{NAME} $0"),
        CodeSnippet(trigger: "printf", detail: "printf", body: "printf(\"$1{%d}\\n\", $0);"),
        CodeSnippet(trigger: "scanf", detail: "scanf", body: "scanf(\"$1{%d}\", &$0);"),
        CodeSnippet(trigger: "struct", detail: "struct", body: "struct $1{Name} {\n\t$0\n};"),
        CodeSnippet(trigger: "func", detail: "function", body: "$1{void} $2name() {\n\t$0\n}")
    ]

    private static let swift: [CodeSnippet] = [
        CodeSnippet(trigger: "for", detail: "for-in loop", body: "for $1{item} in $0 {\n\t\n}"),
        CodeSnippet(trigger: "while", detail: "while loop", body: "while $1{condition} {\n\t$0\n}"),
        CodeSnippet(trigger: "if", detail: "if statement", body: "if $1{condition} {\n\t$0\n}"),
        CodeSnippet(trigger: "guard", detail: "guard let", body: "guard let $1{value} else {\n\treturn\n}\n$0"),
        CodeSnippet(trigger: "func", detail: "function", body: "func $1{name}() {\n\t$0\n}"),
        CodeSnippet(trigger: "switch", detail: "switch", body: "switch $1{value} {\ncase $0:\n\tbreak\ndefault:\n\tbreak\n}")
    ]

    private static let python: [CodeSnippet] = [
        CodeSnippet(trigger: "for", detail: "for loop", body: "for $1{item} in $0:\n\t"),
        CodeSnippet(trigger: "while", detail: "while loop", body: "while $1{condition}:\n\t$0"),
        CodeSnippet(trigger: "if", detail: "if statement", body: "if $1{condition}:\n\t$0"),
        CodeSnippet(trigger: "def", detail: "function", body: "def $1{name}():\n\t$0"),
        CodeSnippet(trigger: "main", detail: "main guard", body: "if __name__ == \"__main__\":\n\t$0")
    ]

    private static let javascript: [CodeSnippet] = [
        CodeSnippet(trigger: "for", detail: "for loop", body: "for (let i = 0; i < $1{count}; i++) {\n\t$0\n}"),
        CodeSnippet(trigger: "forof", detail: "for-of loop", body: "for (const $1{item} of $0) {\n\t\n}"),
        CodeSnippet(trigger: "while", detail: "while loop", body: "while ($1{condition}) {\n\t$0\n}"),
        CodeSnippet(trigger: "if", detail: "if statement", body: "if ($1{condition}) {\n\t$0\n}"),
        CodeSnippet(trigger: "function", detail: "function", body: "function $1{name}() {\n\t$0\n}")
    ]

    private static let go: [CodeSnippet] = [
        CodeSnippet(trigger: "for", detail: "for loop", body: "for i := 0; i < $1{count}; i++ {\n\t$0\n}"),
        CodeSnippet(trigger: "if", detail: "if statement", body: "if $1{condition} {\n\t$0\n}"),
        CodeSnippet(trigger: "func", detail: "function", body: "func $1{name}() {\n\t$0\n}")
    ]

    private static let rust: [CodeSnippet] = [
        CodeSnippet(trigger: "for", detail: "for loop", body: "for $1{item} in $0 {\n\t\n}"),
        CodeSnippet(trigger: "while", detail: "while loop", body: "while $1{condition} {\n\t$0\n}"),
        CodeSnippet(trigger: "if", detail: "if statement", body: "if $1{condition} {\n\t$0\n}"),
        CodeSnippet(trigger: "fn", detail: "function", body: "fn $1{name}() {\n\t$0\n}")
    ]
}

enum SnippetExpander {
    /// Expands a snippet at the given indentation, returning the text to insert
    /// and the range to select afterwards (the `$1` placeholder, else the `$0`
    /// caret, else nil for "place caret at the end"). Offsets are relative to
    /// the start of the inserted text.
    static func expand(_ snippet: CodeSnippet, baseIndent: String, indentUnit: String) -> (text: String, selection: NSRange?) {
        var lines = snippet.body.components(separatedBy: "\n")
        for index in lines.indices {
            lines[index] = lines[index].replacingOccurrences(of: "\t", with: indentUnit)
            if index > 0 { lines[index] = baseIndent + lines[index] }
        }
        let raw = lines.joined(separator: "\n")

        var out = ""
        var selection: NSRange?
        var caret: Int?
        var i = raw.startIndex
        while i < raw.endIndex {
            let char = raw[i]
            if char == "$", let parsed = parseMarker(raw, at: i, output: out) {
                switch parsed.kind {
                case .caret:
                    caret = (out as NSString).length
                case .placeholder(let text):
                    let start = (out as NSString).length
                    out += text
                    selection = NSRange(location: start, length: (text as NSString).length)
                }
                i = parsed.next
                continue
            }
            out.append(char)
            i = raw.index(after: i)
        }

        return (out, selection ?? caret.map { NSRange(location: $0, length: 0) })
    }

    private enum MarkerKind { case caret; case placeholder(String) }

    private static func parseMarker(_ raw: String, at index: String.Index, output: String) -> (kind: MarkerKind, next: String.Index)? {
        let afterDollar = raw.index(after: index)
        guard afterDollar < raw.endIndex else { return nil }
        let marker = raw[afterDollar]
        if marker == "0" {
            return (.caret, raw.index(after: afterDollar))
        }
        // $1{text} — selectable placeholder.
        guard marker == "1" else { return nil }
        let brace = raw.index(after: afterDollar)
        guard brace < raw.endIndex, raw[brace] == "{" else {
            // Bare $1 with no braces: treat as empty placeholder.
            return (.placeholder(""), raw.index(after: afterDollar))
        }
        var j = raw.index(after: brace)
        var inner = ""
        while j < raw.endIndex, raw[j] != "}" {
            inner.append(raw[j])
            j = raw.index(after: j)
        }
        let next = j < raw.endIndex ? raw.index(after: j) : j
        return (.placeholder(inner), next)
    }
}
