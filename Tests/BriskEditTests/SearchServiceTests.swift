import XCTest
import Darwin
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

    func testCancellationTerminatesRipgrepProcess() async throws {
        let root = try makeTemporaryDirectory()
        let pidFile = root.appendingPathComponent("pid")
        let executable = root.appendingPathComponent("fake-rg")
        let script = "#!/bin/sh\nprintf '%s' $$ > '\(pidFile.path)'\nexec /bin/sleep 30\n"
        try script.write(to: executable, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: executable.path)

        let task = Task {
            await SearchService.searchWithFeedback(
                SearchQuery(text: "needle"), root: root, includeHidden: true,
                ripgrepPathOverride: executable.path
            )
        }
        defer { task.cancel() }
        var pid: Int32?
        for _ in 0..<500 {
            if let text = try? String(contentsOf: pidFile, encoding: .utf8), let value = Int32(text.trimmingCharacters(in: .whitespacesAndNewlines)) {
                pid = value
                break
            }
            try await Task.sleep(for: .milliseconds(10))
        }
        guard let runningPID = pid else {
            task.cancel()
            let response = await task.value
            return XCTFail("Search fixture did not start: \(response.errorMessage ?? "no process identifier")")
        }
        let started = ContinuousClock.now
        task.cancel()
        _ = await task.value

        XCTAssertLessThan(started.duration(to: .now), .seconds(2))
        XCTAssertNotEqual(kill(runningPID, 0), 0)
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
