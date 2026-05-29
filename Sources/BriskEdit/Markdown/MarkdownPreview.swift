import SwiftUI
import WebKit

struct MarkdownPreview: View {
    let document: TextDocument

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
            MarkdownWebView(html: MarkdownRenderer.html(for: document.text))
        }
    }
}

private struct MarkdownWebView: NSViewRepresentable {
    let html: String

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeNSView(context: Context) -> WKWebView {
        let view = WKWebView()
        view.setValue(false, forKey: "drawsBackground")
        return view
    }

    func updateNSView(_ webView: WKWebView, context: Context) {
        guard context.coordinator.lastHTML != html else { return }
        context.coordinator.lastHTML = html
        webView.loadHTMLString(html, baseURL: nil)
    }

    final class Coordinator {
        var lastHTML: String?
    }
}

enum MarkdownRenderer {
    static func html(for markdown: String) -> String {
        let body = markdown
            .split(separator: "\n", omittingEmptySubsequences: false)
            .map(renderLine)
            .joined(separator: "\n")
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

    private static func renderLine(_ rawLine: Substring) -> String {
        let line = String(rawLine)
        if line.hasPrefix("### ") { return "<h3>\(inline(line.dropFirst(4)))</h3>" }
        if line.hasPrefix("## ") { return "<h2>\(inline(line.dropFirst(3)))</h2>" }
        if line.hasPrefix("# ") { return "<h1>\(inline(line.dropFirst(2)))</h1>" }
        if line.hasPrefix("> ") { return "<blockquote>\(inline(line.dropFirst(2)))</blockquote>" }
        if line.hasPrefix("- ") { return "<ul><li>\(inline(line.dropFirst(2)))</li></ul>" }
        if line.trimmingCharacters(in: .whitespaces).isEmpty { return "<br>" }
        return "<p>\(inline(Substring(line)))</p>"
    }

    private static func inline(_ text: Substring) -> String {
        escape(String(text))
            .replacingOccurrences(of: "**([^*]+)**", with: "<strong>$1</strong>", options: .regularExpression)
            .replacingOccurrences(of: "`([^`]+)`", with: "<code>$1</code>", options: .regularExpression)
    }

    private static func escape(_ text: String) -> String {
        text
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
    }
}
