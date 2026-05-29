import XCTest
@testable import BriskEdit

@MainActor
final class RunServiceTests: XCTestCase {
    private var temporaryDirectories: [URL] = []

    override func tearDownWithError() throws {
        for url in temporaryDirectories {
            try? FileManager.default.removeItem(at: url)
        }
        temporaryDirectories.removeAll()
        try super.tearDownWithError()
    }

    func testShellQuoteEscapesSingleQuotes() {
        XCTAssertEqual(RunService.shellQuote("/tmp/it's fine.py"), "'/tmp/it'\\''s fine.py'")
    }

    func testResolvePythonUsesWorkspaceRootAsWorkingDirectory() throws {
        let root = try makeTemporaryDirectory()
        let file = root.appendingPathComponent("Scripts/hello.py")
        try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        try "print('hi')".write(to: file, atomically: true, encoding: .utf8)

        let document = TextDocument(fileURL: file, text: "print('hi')", encoding: .utf8)
        let command = try RunService.resolve(document: document, workspaceRoot: root)

        XCTAssertEqual(command.title, "Run hello.py")
        XCTAssertEqual(command.cwd, root)
        XCTAssertEqual(command.shellLine, "python3 \(RunService.shellQuote(file.path))")
    }

    func testResolveSwiftPackageRunsFromPackageRoot() throws {
        let root = try makeTemporaryDirectory()
        let package = root.appendingPathComponent("Package.swift")
        let source = root.appendingPathComponent("Sources/App/main.swift")
        try "// swift-tools-version: 6.0\n".write(to: package, atomically: true, encoding: .utf8)
        try FileManager.default.createDirectory(at: source.deletingLastPathComponent(), withIntermediateDirectories: true)
        try "print(\"hi\")".write(to: source, atomically: true, encoding: .utf8)

        let document = TextDocument(fileURL: source, text: "print(\"hi\")", encoding: .utf8)
        let command = try RunService.resolve(document: document, workspaceRoot: root)

        XCTAssertEqual(command.title, "swift run")
        XCTAssertEqual(command.cwd, root)
        XCTAssertEqual(command.shellLine, "swift run")
    }

    private func makeTemporaryDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("briskedit-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        temporaryDirectories.append(url)
        return url
    }
}
