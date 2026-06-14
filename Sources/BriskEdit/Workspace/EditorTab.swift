import Foundation
import Observation

enum PreviewKind: Equatable {
    case pdf(URL)
    case quickLook(URL)
    case image(URL)

    var url: URL {
        switch self {
        case .pdf(let url), .quickLook(let url), .image(let url):
            url
        }
    }

    var systemImage: String {
        switch self {
        case .pdf:
            "doc.richtext"
        case .quickLook:
            "doc.text.magnifyingglass"
        case .image:
            "photo"
        }
    }

    static func previewKind(for url: URL) -> PreviewKind? {
        switch url.pathExtension.lowercased() {
        case "pdf":
            .pdf(url)
        case "docx":
            .quickLook(url)
        case "png", "jpg", "jpeg", "gif", "bmp", "tiff", "tif", "heic", "heif", "webp", "ico", "icns":
            .image(url)
        default:
            nil
        }
    }
}

enum SplitPreviewContent: Equatable {
    case native(PreviewKind)
    case markdown(EditorTab.ID)

    static func supports(_ url: URL) -> Bool {
        PreviewKind.previewKind(for: url) != nil
            || SourceLanguage(url: url, displayName: url.lastPathComponent) == .markdown
    }
}

/// Non-file tabs that show a built-in page instead of a document or preview.
enum SpecialTabContent: Equatable {
    case whatsNew(version: String)

    var title: String {
        switch self {
        case .whatsNew: "What's New"
        }
    }

    var symbol: String {
        switch self {
        case .whatsNew: "sparkles"
        }
    }
}

@MainActor
@Observable
final class EditorTab: Identifiable {
    let id: UUID = UUID()
    let document: TextDocument
    /// When set, the tab shows a native preview instead of the text editor.
    let previewKind: PreviewKind?
    /// When set, the tab shows a built-in page (e.g. What's New) — no document.
    let special: SpecialTabContent?

    init(document: TextDocument, previewKind: PreviewKind? = nil, special: SpecialTabContent? = nil) {
        self.document = document
        self.previewKind = previewKind
        self.special = special
    }

    /// Tab-strip title: the special page's title, otherwise the document name.
    var displayTitle: String {
        special?.title ?? document.displayName
    }

    static func preview(_ kind: PreviewKind) -> EditorTab {
        EditorTab(document: TextDocument(fileURL: kind.url, text: "", encoding: .utf8), previewKind: kind)
    }

    static func whatsNew(version: String) -> EditorTab {
        EditorTab(document: TextDocument(fileURL: nil, text: "", encoding: .utf8), special: .whatsNew(version: version))
    }
}
