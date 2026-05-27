import Foundation
import Observation

@MainActor
@Observable
final class EditorTab: Identifiable {
    let id: UUID = UUID()
    let document: TextDocument

    init(document: TextDocument) {
        self.document = document
    }
}
