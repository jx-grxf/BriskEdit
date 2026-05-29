import Foundation
import Observation

@MainActor
@Observable
final class EditorTab: Identifiable {
    let id: UUID = UUID()
    let document: TextDocument
    /// When set, the tab shows a PDF viewer instead of the text editor.
    let pdfURL: URL?

    init(document: TextDocument, pdfURL: URL? = nil) {
        self.document = document
        self.pdfURL = pdfURL
    }

    static func pdf(url: URL) -> EditorTab {
        EditorTab(document: TextDocument(fileURL: url, text: "", encoding: .utf8), pdfURL: url)
    }
}
