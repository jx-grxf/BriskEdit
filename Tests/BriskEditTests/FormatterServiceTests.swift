import XCTest
@testable import BriskEdit

final class FormatterServiceTests: XCTestCase {
    private var temporaryDirectories: [URL] = []

    override func tearDown() {
        for directory in temporaryDirectories {
            try? FileManager.default.removeItem(at: directory)
        }
        temporaryDirectories.removeAll()
        super.tearDown()
    }

    func testClangConfigLookupFindsAncestorConfig() throws {
        let root = try makeTemporaryDirectory()
        let nested = root.appendingPathComponent("Sources/App", isDirectory: true)
        try FileManager.default.createDirectory(at: nested, withIntermediateDirectories: true)
        try "BasedOnStyle: LLVM\n".write(
            to: root.appendingPathComponent(".clang-format"),
            atomically: true,
            encoding: .utf8
        )

        XCTAssertTrue(FormatterService.hasClangFormatConfig(startingFrom: nested))
    }

    func testClangConfigLookupTerminatesForDecomposedUnicodePath() throws {
        let root = try makeTemporaryDirectory()
        let nested = root.appendingPathComponent("4. PLF U\u{0308}ben", isDirectory: true)
        try FileManager.default.createDirectory(at: nested, withIntermediateDirectories: true)

        XCTAssertFalse(FormatterService.hasClangFormatConfig(startingFrom: nested))
    }

    func testClangConfigLookupRejectsNonFileURL() throws {
        let url = try XCTUnwrap(URL(string: "https://example.com/project/source.c"))

        XCTAssertFalse(FormatterService.hasClangFormatConfig(startingFrom: url))
    }

    func testRequestGateRejectsOverlappingWork() async {
        let gate = FormatterRequestGate()

        let firstRequestAccepted = await gate.begin()
        let overlappingRequestAccepted = await gate.begin()
        let suppressedRequests = await gate.finish()
        let nextRequestAccepted = await gate.begin()
        _ = await gate.finish()

        XCTAssertTrue(firstRequestAccepted)
        XCTAssertFalse(overlappingRequestAccepted)
        XCTAssertEqual(suppressedRequests, 1)
        XCTAssertTrue(nextRequestAccepted)
    }

    func testFormatsCFileInDecomposedUnicodeDirectory() async throws {
        let probe = BoundedProcessRunner.run(
            executableURL: URL(fileURLWithPath: "/bin/zsh"),
            arguments: ["-lc", "command -v clang-format"],
            timeout: 2,
            maximumStandardOutputBytes: 64 * 1024,
            maximumStandardErrorBytes: 64 * 1024
        )
        try XCTSkipIf(probe?.terminationStatus != 0, "clang-format is not installed")

        let root = try makeTemporaryDirectory()
        let nested = root.appendingPathComponent("4. PLF U\u{0308}ben", isDirectory: true)
        try FileManager.default.createDirectory(at: nested, withIntermediateDirectories: true)
        let fileURL = nested.appendingPathComponent("main.c")
        let source = "int main(){return 0;}\n"

        let formatted = await FormatterService.format(
            text: source,
            language: .c,
            fileURL: fileURL,
            indentWidth: 4
        )

        XCTAssertEqual(formatted, "int main() { return 0; }\n")
    }

    func testConcurrentFormatRequestsRunOnlyOneFormatter() async throws {
        let probe = BoundedProcessRunner.run(
            executableURL: URL(fileURLWithPath: "/bin/zsh"),
            arguments: ["-lc", "command -v clang-format"],
            timeout: 2,
            maximumStandardOutputBytes: 64 * 1024,
            maximumStandardErrorBytes: 64 * 1024
        )
        try XCTSkipIf(probe?.terminationStatus != 0, "clang-format is not installed")

        let root = try makeTemporaryDirectory()
        let fileURL = root.appendingPathComponent("main.c")
        let source = String(repeating: "int value(){return 1;}\n", count: 2_000)
        let completed = await withTaskGroup(of: Bool.self, returning: Int.self) { group in
            for _ in 0..<100 {
                group.addTask {
                    await FormatterService.format(text: source, language: .c, fileURL: fileURL) != nil
                }
            }
            var count = 0
            for await succeeded in group where succeeded { count += 1 }
            return count
        }

        XCTAssertEqual(completed, 1)
    }

    private func makeTemporaryDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("briskedit-formatter-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        temporaryDirectories.append(url)
        return url
    }
}
