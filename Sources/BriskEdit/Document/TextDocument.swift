import Foundation
import Observation

@MainActor
@Observable
final class TextDocument {
    private(set) var fileURL: URL?
    private(set) var encoding: String.Encoding
    var text: String
    var isDirty: Bool = false

    var displayName: String {
        fileURL?.lastPathComponent ?? "Untitled"
    }

    init(fileURL: URL?, text: String, encoding: String.Encoding) {
        self.fileURL = fileURL
        self.text = text
        self.encoding = encoding
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
        isDirty = true
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
}
