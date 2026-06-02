import SwiftUI
import WebKit

struct MarkdownPreview: View {
    let document: TextDocument
    @State private var html = ""
    @State private var renderTask: Task<Void, Never>?

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Label("Preview", systemImage: "doc.richtext")
                    .font(.caption.weight(.semibold))
                Spacer()
                Text(document.displayName)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 10)
            .frame(height: 34)
            .background(.bar)
            Divider()
            MarkdownWebView(html: html, baseURL: document.fileURL?.deletingLastPathComponent())
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
                try? await Task.sleep(for: .milliseconds(180))
            }
            guard !Task.isCancelled else { return }
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
    let baseURL: URL?

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeNSView(context: Context) -> WKWebView {
        let view = WKWebView()
        view.setValue(false, forKey: "drawsBackground")
        view.navigationDelegate = context.coordinator
        return view
    }

    func updateNSView(_ webView: WKWebView, context: Context) {
        guard context.coordinator.lastHTML != html else { return }
        context.coordinator.lastHTML = html
        webView.evaluateJavaScript("[window.scrollX, window.scrollY]") { value, _ in
            if let pair = value as? [Double], pair.count == 2 {
                context.coordinator.pendingScroll = CGPoint(x: pair[0], y: pair[1])
            }
            webView.loadHTMLString(html, baseURL: baseURL)
        }
    }

    final class Coordinator: NSObject, WKNavigationDelegate {
        var lastHTML: String?
        var pendingScroll: CGPoint?

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            guard let pendingScroll else { return }
            self.pendingScroll = nil
            webView.evaluateJavaScript("window.scrollTo(\(pendingScroll.x), \(pendingScroll.y));")
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
          line-height: 1.55;
          max-width: 860px;
          margin: 24px auto;
          padding: 0 28px 48px;
          color: CanvasText;
          background: Canvas;
        }
        pre, code {
          font-family: ui-monospace, SFMono-Regular, Menlo, monospace;
          background: color-mix(in srgb, CanvasText 8%, transparent);
          border-radius: 5px;
        }
        code { padding: 2px 4px; }
        pre { padding: 12px; overflow-x: auto; }
        img { max-width: 100%; height: auto; }
        table { border-collapse: collapse; width: 100%; margin: 12px 0; }
        th, td { border: 1px solid color-mix(in srgb, CanvasText 18%, transparent); padding: 6px 8px; text-align: left; }
        th { background: color-mix(in srgb, CanvasText 8%, transparent); }
        blockquote {
          border-left: 3px solid color-mix(in srgb, CanvasText 28%, transparent);
          margin-left: 0;
          padding-left: 14px;
          color: color-mix(in srgb, CanvasText 70%, transparent);
        }
        a { color: LinkText; }
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
            } else if line.hasPrefix("- ") {
                var items: [String] = []
                while index < lines.count, lines[index].hasPrefix("- ") {
                    items.append("<li>\(inline(lines[index].dropFirst(2)))</li>")
                    index += 1
                }
                html.append("<ul>\(items.joined())</ul>")
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
            } else if line.hasPrefix("### ") {
                html.append("<h3>\(inline(line.dropFirst(4)))</h3>")
            } else if line.hasPrefix("## ") {
                html.append("<h2>\(inline(line.dropFirst(3)))</h2>")
            } else if line.hasPrefix("# ") {
                html.append("<h1>\(inline(line.dropFirst(2)))</h1>")
            } else if line.hasPrefix("> ") {
                html.append("<blockquote>\(inline(line.dropFirst(2)))</blockquote>")
            } else if line.trimmingCharacters(in: .whitespaces).isEmpty {
                html.append("<br>")
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
        escape(String(text))
            .replacingOccurrences(of: #"!\[([^\]]*)\]\(([^)]+)\)"#, with: "<img src=\"$2\" alt=\"$1\">", options: .regularExpression)
            .replacingOccurrences(of: #"\[([^\]]+)\]\(([^)]+)\)"#, with: "<a href=\"$2\">$1</a>", options: .regularExpression)
            .replacingOccurrences(of: "**([^*]+)**", with: "<strong>$1</strong>", options: .regularExpression)
            .replacingOccurrences(of: "`([^`]+)`", with: "<code>$1</code>", options: .regularExpression)
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
