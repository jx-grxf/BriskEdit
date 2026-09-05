import Foundation
import Observation

struct ReferenceResult: Identifiable, Sendable, Equatable {
    let url: URL
    let line: Int
    let column: Int
    var id: String { "\(url.absoluteString):\(line):\(column)" }
}

@MainActor @Observable
final class WorkspaceReviewModel {
    var showComparison = false
    var comparisonTitle = "Compare"
    var comparisonText = ""
    var comparisonError: String?
    var comparisonLoading = false
    var showReferences = false
    var referenceTitle = "References"
    var references: [ReferenceResult] = []
    var referencesError: String?
    var referencesLoading = false
    @ObservationIgnored private var comparisonTask: Task<Void, Never>?
    @ObservationIgnored private var referencesTask: Task<Void, Never>?

    func compare(document: TextDocument) {
        guard let url = document.fileURL else { return }
        let text = document.text
        beginComparison(title: "\(document.displayName) — Disk ↔ Editor") {
            try await TextComparisonService.compareWithDisk(file: url, text: text)
        }
    }

    func gitDiff(file: URL, root: URL, staged: Bool) {
        beginComparison(title: "\(file.lastPathComponent) — \(staged ? "HEAD ↔ Index" : "Index ↔ Working Tree")") {
            try await GitService.diffText(for: file, root: root, staged: staged)
        }
    }

    private func beginComparison(title: String, load: @escaping @Sendable () async throws -> String) {
        comparisonTask?.cancel()
        comparisonTitle = title
        comparisonText = ""
        comparisonError = nil
        comparisonLoading = true
        showComparison = true
        comparisonTask = Task { [weak self] in
            do {
                let text = try await load()
                guard !Task.isCancelled else { return }
                self?.comparisonText = text
            } catch {
                guard !Task.isCancelled else { return }
                self?.comparisonError = error.localizedDescription
            }
            self?.comparisonLoading = false
        }
    }

    func findReferences(document: TextDocument, root: URL?, line: Int? = nil, character: Int? = nil) {
        guard let url = document.fileURL else { return }
        referencesTask?.cancel()
        referenceTitle = "References — \(document.displayName)"
        references = []
        referencesError = nil
        referencesLoading = true
        showReferences = true
        let text = document.text
        let language = document.language
        let revision = document.revision
        let row = line ?? max(0, document.cursorLine - 1)
        let column = character ?? max(0, document.cursorColumn - 1)
        referencesTask = Task { [weak self, weak document] in
            do {
                let locations = try await LSPService.shared.references(
                    language: language, uri: url.absoluteString, text: text,
                    line: row, character: column, root: root?.path ?? url.deletingLastPathComponent().path
                )
                guard !Task.isCancelled else { return }
                guard document?.revision == revision else {
                    throw TextComparisonError.failed("The document changed. Run Find References again.")
                }
                var seen = Set<String>()
                self?.references = locations.compactMap { location in
                    guard let target = URL(string: location.uri), target.isFileURL else { return nil }
                    let result = ReferenceResult(url: target, line: location.line, column: location.column)
                    return seen.insert(result.id).inserted ? result : nil
                }.sorted { ($0.url.path, $0.line, $0.column) < ($1.url.path, $1.line, $1.column) }
            } catch {
                guard !Task.isCancelled else { return }
                self?.referencesError = error.localizedDescription
            }
            self?.referencesLoading = false
        }
    }

    func cancelComparison() { comparisonTask?.cancel() }
    func cancelReferences() { referencesTask?.cancel() }
}
