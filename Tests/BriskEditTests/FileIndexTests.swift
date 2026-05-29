import XCTest
@testable import BriskEdit

final class FileIndexTests: XCTestCase {
    private var temporaryDirectories: [URL] = []

    override func tearDownWithError() throws {
        for url in temporaryDirectories {
            try? FileManager.default.removeItem(at: url)
        }
        temporaryDirectories.removeAll()
        try super.tearDownWithError()
    }

    func testFileIndexSkipsHiddenAndBuildDirectoriesByDefault() throws {
        let root = try makeTemporaryDirectory()
        try writeFile("Sources/App.swift", under: root)
        try writeFile(".hidden.swift", under: root)
        try writeFile(".git/config", under: root)
        try writeFile("node_modules/pkg/index.js", under: root)

        let files = FileIndex.files(under: root, includeHidden: false, limit: 100)
            .map(\.lastPathComponent)

        XCTAssertEqual(files, ["App.swift"])
    }

    func testFileSearchTreatsExtensionQueriesStrictly() throws {
        let root = try makeTemporaryDirectory()
        try writeFile("main.c", under: root)
        try writeFile("main.cpp", under: root)
        try writeFile("style.css", under: root)

        let matches = FileNode.search(in: root, query: ".c", codeOnly: true)
            .map(\.name)

        XCTAssertEqual(matches, ["main.c"])
    }

    private func makeTemporaryDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("briskedit-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        temporaryDirectories.append(url)
        return url
    }

    private func writeFile(_ path: String, under root: URL) throws {
        let url = root.appendingPathComponent(path)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data().write(to: url)
    }

    private func relativePath(_ url: URL, root: URL) -> String {
        String(url.path.dropFirst(root.path.count + 1))
    }
}
