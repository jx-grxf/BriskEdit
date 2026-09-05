import XCTest
@testable import BriskEdit

@MainActor
final class RunServiceTests: XCTestCase {
    nonisolated(unsafe) private var temporaryDirectories: [URL] = []

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

    func testResolvePythonUsesWorkspaceRootAsWorkingDirectory() async throws {
        let root = try makeTemporaryDirectory()
        let file = root.appendingPathComponent("Scripts/hello.py")
        try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        try "print('hi')".write(to: file, atomically: true, encoding: .utf8)

        let document = TextDocument(fileURL: file, text: "print('hi')", encoding: .utf8)
        let command = try await RunService.resolve(document: document, workspaceRoot: root)

        XCTAssertEqual(command.title, "Run hello.py")
        XCTAssertEqual(command.cwd, root)
        XCTAssertEqual(command.shellLine, "python3 \(RunService.shellQuote(file.path))")
    }

    func testResolveSwiftPackageRunsFromPackageRoot() async throws {
        let root = try makeTemporaryDirectory()
        let package = root.appendingPathComponent("Package.swift")
        let source = root.appendingPathComponent("Sources/App/main.swift")
        try "// swift-tools-version: 6.0\n".write(to: package, atomically: true, encoding: .utf8)
        try FileManager.default.createDirectory(at: source.deletingLastPathComponent(), withIntermediateDirectories: true)
        try "print(\"hi\")".write(to: source, atomically: true, encoding: .utf8)

        let document = TextDocument(fileURL: source, text: "print(\"hi\")", encoding: .utf8)
        let command = try await RunService.resolve(document: document, workspaceRoot: root)

        XCTAssertEqual(command.title, "swift run")
        XCTAssertEqual(command.cwd, root)
        XCTAssertEqual(command.shellLine, "swift run")
    }

    func testDirtySwiftPackageRequiresSaveBeforeRun() throws {
        let root = try makeTemporaryDirectory()
        let package = root.appendingPathComponent("Package.swift")
        let source = root.appendingPathComponent("Sources/App/main.swift")
        try "// swift-tools-version: 6.0\n".write(to: package, atomically: true, encoding: .utf8)
        try FileManager.default.createDirectory(at: source.deletingLastPathComponent(), withIntermediateDirectories: true)
        try "print(\"old\")".write(to: source, atomically: true, encoding: .utf8)

        let document = TextDocument(fileURL: source, text: "print(\"old\")", encoding: .utf8)
        document.applyEdit(text: "print(\"new\")")

        XCTAssertTrue(RunService.requiresSaveBeforeRun(document: document, workspaceRoot: root))
    }

    func testResolveGoModuleRunsFromNestedModuleRoot() async throws {
        let workspace = try makeTemporaryDirectory()
        let moduleRoot = workspace.appendingPathComponent("Tools/Worker", isDirectory: true)
        let source = moduleRoot.appendingPathComponent("cmd/main.go")
        try FileManager.default.createDirectory(at: source.deletingLastPathComponent(), withIntermediateDirectories: true)
        try "module example.com/worker\n".write(to: moduleRoot.appendingPathComponent("go.mod"), atomically: true, encoding: .utf8)
        try "package main\nfunc main() {}\n".write(to: source, atomically: true, encoding: .utf8)

        let document = TextDocument(fileURL: source, text: "package main\nfunc main() {}\n", encoding: .utf8)
        let command = try await RunService.resolve(document: document, workspaceRoot: workspace)

        XCTAssertEqual(command.title, "go run")
        XCTAssertEqual(command.cwd, moduleRoot)
        XCTAssertEqual(command.shellLine, "go run .")
    }

    func testDirtyCSourceMaterializesBesideFileForLocalHeaders() async throws {
        let root = try makeTemporaryDirectory()
        let source = root.appendingPathComponent("main.c")
        try "#include \"local.h\"\nint main(){return 0;}".write(to: source, atomically: true, encoding: .utf8)

        let document = TextDocument(fileURL: source, text: "#include \"local.h\"\nint main(){return 0;}", encoding: .utf8)
        document.applyEdit(text: "#include \"local.h\"\nint main(){return 1;}")

        let command = try await RunService.resolve(document: document, workspaceRoot: root)

        XCTAssertEqual(command.cwd, root)
        XCTAssertTrue(command.shellLine.contains(root.path))
        XCTAssertTrue(command.shellLine.contains(".briskedit-run-"))
    }

    func testResolveJavaCompilesPublicClassNameFromTemporarySource() async throws {
        let root = try makeTemporaryDirectory()
        let source = root.appendingPathComponent("test.java")
        let text = """
        public class Main {
            public static void main(String[] args) {
                System.out.println("Hello World");
            }
        }
        """
        try text.write(to: source, atomically: true, encoding: .utf8)

        let document = TextDocument(fileURL: source, text: text, encoding: .utf8)
        let command = try await RunService.resolve(document: document, workspaceRoot: root)

        XCTAssertEqual(command.title, "Run test.java")
        XCTAssertEqual(command.cwd, root)
        XCTAssertTrue(command.shellLine.contains("\"$__brisk_javac\" -d"))
        XCTAssertTrue(command.shellLine.contains("brew --prefix openjdk"))
        XCTAssertTrue(command.shellLine.contains("Main.java"))
        XCTAssertTrue(command.shellLine.contains("\"$__brisk_java\" -cp"))
        XCTAssertTrue(command.shellLine.contains("'Main'"))
    }

    private func makeTemporaryDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("briskedit-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        temporaryDirectories.append(url)
        return url
    }
}
