import XCTest
@testable import BriskEdit

final class SearchServiceTests: XCTestCase {
    private var temporaryDirectories: [URL] = []

    override func tearDownWithError() throws {
        for url in temporaryDirectories {
            try? FileManager.default.removeItem(at: url)
        }
        temporaryDirectories.removeAll()
        try super.tearDownWithError()
    }

    func testInvalidRegexReportsError() async throws {
        let root = try makeTemporaryDirectory()
        try writeFile("main.swift", "print(\"hello\")", under: root)

        let response = await SearchService.searchWithFeedback(
            SearchQuery(text: "(", isRegex: true),
            root: root,
            includeHidden: true
        )

        XCTAssertTrue(response.results.isEmpty)
        XCTAssertNotNil(response.errorMessage)
    }

    func testMatchLimitIsReported() async throws {
        let root = try makeTemporaryDirectory()
        try writeFile("many.txt", Array(repeating: "needle", count: 20).joined(separator: "\n"), under: root)

        let response = await SearchService.searchWithFeedback(
            SearchQuery(text: "needle"),
            root: root,
            includeHidden: true,
            matchLimit: 3
        )

        XCTAssertEqual(response.results.reduce(0) { $0 + $1.matches.count }, 3)
        XCTAssertTrue(response.reachedMatchLimit)
    }

    private func makeTemporaryDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("briskedit-search-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        temporaryDirectories.append(url)
        return url
    }

    private func writeFile(_ path: String, _ contents: String, under root: URL) throws {
        let url = root.appendingPathComponent(path)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try contents.write(to: url, atomically: true, encoding: .utf8)
    }
}
