import AppKit
import SwiftUI
import WebKit

struct MarkdownPreview: View {
    let document: TextDocument
    var showsHeader = true
    var renderDebounceMilliseconds = 180
    var onClose: () -> Void = {}
    var onOpenFile: (URL) -> Void = { _ in }
    @State private var html = ""
    @State private var renderTask: Task<Void, Never>?

    var body: some View {
        VStack(spacing: 0) {
            if showsHeader {
                HStack {
                    Label("Preview", systemImage: "doc.richtext")
                        .font(.caption.weight(.semibold))
                    Spacer()
                    Text(document.displayName)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Button("Close Preview", systemImage: "xmark") { onClose() }
                        .buttonStyle(.borderless)
                        .labelStyle(.iconOnly)
                        .help("Close Markdown preview")
                        .accessibilityLabel("Close Markdown preview")
                }
                .padding(.horizontal, 10)
                .frame(height: 34)
                .background(.bar)
                Divider()
            }
            MarkdownWebView(html: html, documentURL: document.fileURL, onOpenFile: onOpenFile)
        }
        .onAppear { scheduleRender(debounce: false) }
        .onChange(of: document.revision) { _, _ in scheduleRender(debounce: true) }
        .onChange(of: document.fileURL) { _, _ in scheduleRender(debounce: false) }
    }

    private func scheduleRender(debounce: Bool) {
        renderTask?.cancel()
        let markdown = document.text
        renderTask = Task {
            if debounce {
                try? await Task.sleep(for: .milliseconds(renderDebounceMilliseconds))
            }
            guard !Task.isCancelled else { return }
            guard markdown.utf8.count <= 4 * 1024 * 1024 else {
                html = "<p>Preview disabled for Markdown files larger than 4 MB.</p>"
                return
            }
            let rendered = await Task.detached(priority: .utility) {
                MarkdownRenderer.html(for: markdown)
            }.value
            guard !Task.isCancelled else { return }
            html = rendered
        }
    }
}

private struct MarkdownWebView: NSViewRepresentable {
    let html: String
    /// The previewed file's own URL. Used as the WebKit base URL so that relative
    /// links/images and in-page `#anchor` links resolve against the document
    /// itself (an anchor stays in the preview instead of opening Finder).
    let documentURL: URL?
    let onOpenFile: (URL) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(documentURL: documentURL, onOpenFile: onOpenFile)
    }

    func makeNSView(context: Context) -> WKWebView {
        let view = WKWebView()
        view.setValue(false, forKey: "drawsBackground")
        view.navigationDelegate = context.coordinator
        return view
    }

    func updateNSView(_ webView: WKWebView, context: Context) {
        context.coordinator.documentURL = documentURL
        context.coordinator.onOpenFile = onOpenFile
        guard context.coordinator.lastHTML != html else { return }
        context.coordinator.lastHTML = html
        webView.evaluateJavaScript("[window.scrollX, window.scrollY]") { value, _ in
            if let pair = value as? [Double], pair.count == 2 {
                context.coordinator.pendingScroll = CGPoint(x: pair[0], y: pair[1])
            }
            webView.loadHTMLString(html, baseURL: documentURL)
        }
    }

    final class Coordinator: NSObject, WKNavigationDelegate {
        var lastHTML: String?
        var pendingScroll: CGPoint?
        var documentURL: URL?
        var onOpenFile: (URL) -> Void

        /// Directory the document lives in — the anchor for relative/wiki links.
        private var baseDirectory: URL? { documentURL?.deletingLastPathComponent() }

        init(documentURL: URL?, onOpenFile: @escaping (URL) -> Void) {
            self.documentURL = documentURL
            self.onOpenFile = onOpenFile
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            guard let pendingScroll else { return }
            self.pendingScroll = nil
            webView.evaluateJavaScript("window.scrollTo(\(pendingScroll.x), \(pendingScroll.y));")
        }

        func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction, decisionHandler: @escaping @MainActor @Sendable (WKNavigationActionPolicy) -> Void) {
            guard navigationAction.navigationType == .linkActivated,
                  let url = navigationAction.request.url else {
                decisionHandler(.allow)
                return
            }
            if url.scheme == "briskedit-wikilink" {
                if let file = resolveWikiLink(url) { onOpenFile(file) }
                decisionHandler(.cancel)
                return
            }
            // In-page anchor (same document, only the fragment differs): let
            // WebKit scroll to it instead of treating it as a navigation.
            if let documentURL, url.isFileURL, url.fragment != nil,
               url.path == documentURL.path {
                decisionHandler(.allow)
                return
            }
            // Relative/absolute link to another local Markdown file → open it.
            if url.isFileURL {
                let target = url.pathExtension.isEmpty
                    ? url.appendingPathExtension("md")
                    : url
                if target.pathExtension.lowercased() == "md",
                   FileManager.default.fileExists(atPath: target.path) {
                    onOpenFile(target)
                    decisionHandler(.cancel)
                    return
                }
                // Any other existing local file: hand off to the editor too.
                if FileManager.default.fileExists(atPath: url.path) {
                    onOpenFile(url)
                    decisionHandler(.cancel)
                    return
                }
            }
            NSWorkspace.shared.open(url)
            decisionHandler(.cancel)
        }

        private func resolveWikiLink(_ url: URL) -> URL? {
            guard let baseDirectory else { return nil }
            let raw = url.host?.removingPercentEncoding ?? url.absoluteString.replacingOccurrences(of: "briskedit-wikilink://", with: "").removingPercentEncoding ?? ""
            let target = raw.split(separator: "#").first.map(String.init) ?? raw
            let candidates = [
                baseDirectory.appendingPathComponent(target),
                baseDirectory.appendingPathComponent(target).appendingPathExtension("md")
            ]
            return candidates.first { FileManager.default.fileExists(atPath: $0.path) }
        }
    }
}

enum MarkdownRenderer {
    static func html(for markdown: String) -> String {
        let body = renderBlocks(markdown)
        return """
        <!doctype html>
        <html>
        <head>
        <meta charset="utf-8">
        <style>
        :root { color-scheme: light dark; }
        body {
          font: -apple-system-body;
          font-size: 15px;
          line-height: 1.6;
          max-width: 820px;
          margin: 0 auto;
          padding: 28px 32px 64px;
          color: CanvasText;
          background: Canvas;
          -webkit-text-size-adjust: 100%;
          word-wrap: break-word;
        }
        h1, h2, h3, h4, h5, h6 { font-weight: 600; line-height: 1.25; margin: 24px 0 16px; }
        h1 { font-size: 1.9em; padding-bottom: .3em; border-bottom: 1px solid color-mix(in srgb, CanvasText 14%, transparent); }
        h2 { font-size: 1.5em; padding-bottom: .3em; border-bottom: 1px solid color-mix(in srgb, CanvasText 12%, transparent); }
        h3 { font-size: 1.25em; }
        h4 { font-size: 1.05em; }
        h5, h6 { font-size: .92em; color: color-mix(in srgb, CanvasText 62%, transparent); }
        p { margin: 0 0 14px; }
        ul, ol { margin: 0 0 14px; padding-left: 1.7em; }
        li { margin: 4px 0; }
        li.task { list-style: none; margin-left: -1.5em; }
        li.task input { margin: 0 8px 0 0; vertical-align: middle; }
        pre, code { font-family: ui-monospace, SFMono-Regular, Menlo, monospace; font-size: .88em; }
        code { background: color-mix(in srgb, CanvasText 9%, transparent); padding: .18em .4em; border-radius: 5px; }
        pre { background: color-mix(in srgb, CanvasText 7%, transparent); padding: 14px 16px; border-radius: 8px; overflow-x: auto; line-height: 1.5; }
        pre code { background: none; padding: 0; border-radius: 0; }
        img { max-width: 100%; height: auto; border-radius: 6px; }
        table { border-collapse: collapse; margin: 0 0 16px; display: block; width: max-content; max-width: 100%; overflow-x: auto; }
        th, td { border: 1px solid color-mix(in srgb, CanvasText 16%, transparent); padding: 7px 12px; text-align: left; }
        th { background: color-mix(in srgb, CanvasText 8%, transparent); font-weight: 600; }
        tr:nth-child(even) td { background: color-mix(in srgb, CanvasText 4%, transparent); }
        blockquote {
          border-left: 3px solid color-mix(in srgb, CanvasText 22%, transparent);
          margin: 0 0 14px;
          padding: 2px 0 2px 16px;
          color: color-mix(in srgb, CanvasText 65%, transparent);
        }
        hr { border: none; height: 1px; background: color-mix(in srgb, CanvasText 14%, transparent); margin: 24px 0; }
        a { color: LinkText; text-decoration: none; }
        a:hover { text-decoration: underline; }
        del { opacity: .7; }
        </style>
        </head>
        <body>
        \(body)
        </body>
        </html>
        """
    }

    private static func renderBlocks(_ markdown: String) -> String {
        let lines = markdown.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        var html: [String] = []
        var index = 0
        while index < lines.count {
            let line = lines[index]
            if line.hasPrefix("```") {
                let language = escape(line.dropFirst(3).trimmingCharacters(in: .whitespaces))
                var code: [String] = []
                index += 1
                while index < lines.count, !lines[index].hasPrefix("```") {
                    code.append(lines[index])
                    index += 1
                }
                let className = language.isEmpty ? "" : " class=\"language-\(language)\""
                html.append("<pre><code\(className)>\(escape(code.joined(separator: "\n")))</code></pre>")
            } else if isHorizontalRule(line) {
                html.append("<hr>")
            } else if line.hasPrefix("- ") || line.hasPrefix("* ") {
                var items: [String] = []
                while index < lines.count, lines[index].hasPrefix("- ") || lines[index].hasPrefix("* ") {
                    items.append(listItem(lines[index].dropFirst(2)))
                    index += 1
                }
                html.append("<ul>\(items.joined())</ul>")
                continue
            } else if orderedMarkerLength(line) != nil {
                var items: [String] = []
                while index < lines.count, let marker = orderedMarkerLength(lines[index]) {
                    items.append("<li>\(inline(lines[index].dropFirst(marker)))</li>")
                    index += 1
                }
                html.append("<ol>\(items.joined())</ol>")
                continue
            } else if isTableHeader(at: index, lines: lines) {
                let headers = tableCells(lines[index]).map { "<th>\(inline($0))</th>" }.joined()
                index += 2
                var rows: [String] = []
                while index < lines.count, lines[index].contains("|"), !lines[index].trimmingCharacters(in: .whitespaces).isEmpty {
                    rows.append("<tr>\(tableCells(lines[index]).map { "<td>\(inline($0))</td>" }.joined())</tr>")
                    index += 1
                }
                html.append("<table><thead><tr>\(headers)</tr></thead><tbody>\(rows.joined())</tbody></table>")
                continue
            } else if line.hasPrefix("###### ") {
                html.append("<h6>\(inline(line.dropFirst(7)))</h6>")
            } else if line.hasPrefix("##### ") {
                html.append("<h5>\(inline(line.dropFirst(6)))</h5>")
            } else if line.hasPrefix("#### ") {
                html.append("<h4>\(inline(line.dropFirst(5)))</h4>")
            } else if line.hasPrefix("### ") {
                html.append("<h3>\(inline(line.dropFirst(4)))</h3>")
            } else if line.hasPrefix("## ") {
                html.append("<h2>\(inline(line.dropFirst(3)))</h2>")
            } else if line.hasPrefix("# ") {
                html.append("<h1>\(inline(line.dropFirst(2)))</h1>")
            } else if line.hasPrefix("> ") {
                html.append("<blockquote>\(inline(line.dropFirst(2)))</blockquote>")
            } else if line.trimmingCharacters(in: .whitespaces).isEmpty {
                // Blank line: block margins handle the spacing; no <br> needed.
            } else {
                html.append("<p>\(inline(Substring(line)))</p>")
            }
            index += 1
        }
        return html.joined(separator: "\n")
    }

    private static func isTableHeader(at index: Int, lines: [String]) -> Bool {
        guard index + 1 < lines.count, lines[index].contains("|") else { return false }
        let separator = lines[index + 1].trimmingCharacters(in: .whitespaces)
        return separator.split(separator: "|").allSatisfy {
            !$0.isEmpty && $0.trimmingCharacters(in: CharacterSet(charactersIn: " :-")).isEmpty
        }
    }

    private static func tableCells(_ line: String) -> [String] {
        let trimmed = line.trimmingCharacters(in: CharacterSet(charactersIn: "|"))
        return trimmed.split(separator: "|").map { String($0).trimmingCharacters(in: .whitespaces) }
    }

    private static func inline(_ text: some StringProtocol) -> String {
        renderWikiLinks(
            escape(String(text))
            .replacingOccurrences(of: #"!\[([^\]]*)\]\(([^)]+)\)"#, with: "<img src=\"$2\" alt=\"$1\">", options: .regularExpression)
            .replacingOccurrences(of: #"\[([^\]]+)\]\(([^)]+)\)"#, with: "<a href=\"$2\">$1</a>", options: .regularExpression)
            .replacingOccurrences(of: "**([^*]+)**", with: "<strong>$1</strong>", options: .regularExpression)
            .replacingOccurrences(of: "~~([^~]+)~~", with: "<del>$1</del>", options: .regularExpression)
            // Italic runs after bold, so any remaining single `*` pairs are emphasis.
            .replacingOccurrences(of: #"\*([^*]+)\*"#, with: "<em>$1</em>", options: .regularExpression)
            .replacingOccurrences(of: "`([^`]+)`", with: "<code>$1</code>", options: .regularExpression)
        )
    }

    /// `---`, `***` or `___` on their own line → a horizontal rule.
    private static func isHorizontalRule(_ line: String) -> Bool {
        let t = line.trimmingCharacters(in: .whitespaces)
        guard t.count >= 3 else { return false }
        return t.allSatisfy { $0 == "-" } || t.allSatisfy { $0 == "*" } || t.allSatisfy { $0 == "_" }
    }

    /// Length of an ordered-list marker like `1. ` (incl. the trailing space), or
    /// nil if the line doesn't start one.
    private static func orderedMarkerLength(_ line: String) -> Int? {
        let chars = Array(line)
        var digits = 0
        while digits < chars.count, chars[digits].isNumber { digits += 1 }
        guard digits > 0, digits + 1 < chars.count, chars[digits] == ".", chars[digits + 1] == " " else { return nil }
        return digits + 2
    }

    /// A list item, rendering `[ ]` / `[x]` as a (disabled) task checkbox.
    private static func listItem(_ raw: Substring) -> String {
        let s = String(raw)
        let lower = s.lowercased()
        if lower.hasPrefix("[ ]") {
            let rest = s.dropFirst(3).drop(while: { $0 == " " })
            return "<li class=\"task\"><input type=\"checkbox\" disabled>\(inline(rest))</li>"
        }
        if lower.hasPrefix("[x]") {
            let rest = s.dropFirst(3).drop(while: { $0 == " " })
            return "<li class=\"task\"><input type=\"checkbox\" checked disabled>\(inline(rest))</li>"
        }
        return "<li>\(inline(raw))</li>"
    }

    private static func renderWikiLinks(_ text: String) -> String {
        guard let regex = try? NSRegularExpression(pattern: #"\[\[([^\]|#]+)(?:#[^\]|]+)?(?:\|([^\]]+))?\]\]"#) else { return text }
        let nsText = text as NSString
        var rendered = text
        for match in regex.matches(in: text, range: NSRange(location: 0, length: nsText.length)).reversed() {
            guard let full = Range(match.range(at: 0), in: rendered),
                  let targetRange = Range(match.range(at: 1), in: text) else { continue }
            let target = String(text[targetRange])
            let label: String
            if match.range(at: 2).location != NSNotFound, let labelRange = Range(match.range(at: 2), in: text) {
                label = String(text[labelRange])
            } else {
                label = target
            }
            let encoded = target.addingPercentEncoding(withAllowedCharacters: .urlHostAllowed) ?? target
            rendered.replaceSubrange(full, with: "<a href=\"briskedit-wikilink://\(encoded)\">\(label)</a>")
        }
        return rendered
    }

    private static func escape(_ text: some StringProtocol) -> String {
        let text = String(text)
        return text
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
    }
}
