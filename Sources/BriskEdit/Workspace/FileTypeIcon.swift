import AppKit
import SwiftUI

/// Shows the real macOS file-type icon (PDF, Markdown, SVG, images, code, …)
/// for an on-disk file. Folders and unsaved buffers fall back to a tinted SF
/// Symbol so the tree stays colorful and consistent.
struct FileTypeIcon: View {
    let url: URL?
    let isDirectory: Bool
    let language: SourceLanguage
    var size: CGFloat = 16

    var body: some View {
        if isDirectory {
            Image(systemName: "folder.fill")
                .foregroundStyle(Color.accentColor)
                .frame(width: size, height: size)
        } else if let icon = Self.icon(for: url) {
            Image(nsImage: icon)
                .resizable()
                .interpolation(.high)
                .frame(width: size, height: size)
        } else {
            Image(systemName: language.iconName)
                .foregroundStyle(Self.tint(language))
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
        case .rust: .brown
        case .markdown: .purple
        case .json, .yaml, .xml: .cyan
        case .html, .css: .pink
        case .shell: .mint
        case .go: .teal
        case .plainText: .secondary
        }
    }
}
