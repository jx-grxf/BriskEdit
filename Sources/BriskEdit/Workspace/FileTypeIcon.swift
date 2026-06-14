import AppKit
import SwiftUI

/// Shows a colorful, Nova-style glyph for each file. Recognized code/markup
/// files render as a tinted SF Symbol per language (so the tree reads at a
/// glance and feels native, instead of the flat grey document icons the system
/// hands back); genuine media files (images, PDFs, binaries) keep their real
/// macOS thumbnail because that preview is actually useful.
struct FileTypeIcon: View {
    let url: URL?
    let isDirectory: Bool
    let language: SourceLanguage
    var size: CGFloat = 16

    var body: some View {
        if isDirectory {
            Image(systemName: "folder.fill")
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(Color.accentColor)
                .font(.system(size: size * 0.95))
                .frame(width: size, height: size)
        } else if language != .plainText {
            // A recognized language → colored glyph, the Nova look.
            Image(systemName: language.iconName)
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(Self.tint(language))
                .font(.system(size: size * 0.9, weight: .medium))
                .frame(width: size, height: size)
        } else if let icon = Self.icon(for: url) {
            // Unrecognized but on disk (image/PDF/binary): real thumbnail.
            Image(nsImage: icon)
                .resizable()
                .interpolation(.high)
                .frame(width: size, height: size)
        } else {
            Image(systemName: "doc.text")
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(.secondary)
                .font(.system(size: size * 0.9))
                .frame(width: size, height: size)
        }
    }

    private static func icon(for url: URL?) -> NSImage? {
        guard let url, FileManager.default.fileExists(atPath: url.path) else { return nil }
        let icon = NSWorkspace.shared.icon(forFile: url.path)
        icon.size = NSSize(width: 32, height: 32)
        return icon
    }

    static func tint(_ language: SourceLanguage) -> Color {
        switch language {
        case .swift: .orange
        case .c, .cpp: .blue
        case .javascript, .typescript: .yellow
        case .php: .indigo
        case .python: .green
        case .rust, .lua: .brown
        case .markdown: .purple
        case .json, .yaml, .xml, .toml, .ini: .cyan
        case .html, .css, .scss, .less: .pink
        case .shell, .perl: .mint
        case .go: .teal
        case .ruby: .red
        case .java, .kotlin: .orange
        case .sql: .blue
        case .dart: .teal
        case .plainText: .secondary
        }
    }
}
