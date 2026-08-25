import XCTest
@testable import BriskEdit

final class EditorConfigServiceTests: XCTestCase {
    // MARK: - Parsing

    func testParseReadsRootFlagAndSections() {
        let parsed = EditorConfigService.parse(
            """
            root = true

            [*]
            indent_style = space
            indent_size = 4

            [*.py]
            indent_style = tab
            """
        )

        XCTAssertTrue(parsed.isRoot)
        XCTAssertEqual(parsed.sections.count, 2)
        XCTAssertEqual(parsed.sections[0].pattern, "*")
        XCTAssertEqual(parsed.sections[0].properties["indent_style"], "space")
        XCTAssertEqual(parsed.sections[0].properties["indent_size"], "4")
        XCTAssertEqual(parsed.sections[1].properties["indent_style"], "tab")
    }

    func testParseIsCaseInsensitiveForPropertyNames() {
        let parsed = EditorConfigService.parse("[*]\nINDENT_STYLE = tab\nTab_Width = 2")

        XCTAssertEqual(parsed.sections[0].properties["indent_style"], "tab")
        XCTAssertEqual(parsed.sections[0].properties["tab_width"], "2")
    }

    func testParseStripsCommentsAndSupportsColonSeparator() {
        let parsed = EditorConfigService.parse(
            """
            # a comment
            ; another one
            [*]
            indent_style : tab ; inline comment
            """
        )

        XCTAssertNil(parsed.sections.first?.properties["indent_size"])
        XCTAssertEqual(parsed.sections[0].properties["indent_style"], "tab")
    }

    // MARK: - Matching and precedence

    func testLaterSectionOverridesEarlier() {
        let file = EditorConfigService.parse(
            """
            [*]
            indent_style = space
            indent_size = 4
            [*.swift]
            indent_size = 2
            """
        )

        let properties = EditorConfigService.matchingProperties(in: file, fileName: "main.swift")

        XCTAssertEqual(properties["indent_style"], "space")
        XCTAssertEqual(properties["indent_size"], "2")
    }

    func testMatchesExactNameStarGlobAndRejectsOthers() {
        XCTAssertTrue(EditorConfigService.matches(pattern: "Makefile", fileName: "Makefile"))
        XCTAssertTrue(EditorConfigService.matches(pattern: "*.swift", fileName: "App.swift"))
        XCTAssertTrue(EditorConfigService.matches(pattern: "*", fileName: "anything.txt"))
        XCTAssertFalse(EditorConfigService.matches(pattern: "*.swift", fileName: "App.py"))
        XCTAssertFalse(EditorConfigService.matches(pattern: "*.md", fileName: "sub/readme.md"))
    }

    // MARK: - Resolution across nested configs

    private var temporaryDirectories: [URL] = []

    override func tearDown() {
        for directory in temporaryDirectories {
            try? FileManager.default.removeItem(at: directory)
        }
        temporaryDirectories.removeAll()
        super.tearDown()
    }

    private func makeTemporaryDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        temporaryDirectories.append(url)
        return url
    }

    private func write(_ content: String, to url: URL) throws {
        try content.write(to: url, atomically: true, encoding: .utf8)
    }

    func testNestedConfigOverridesRootConfigNearestWins() throws {
        let root = try makeTemporaryDirectory()
        let nested = root.appendingPathComponent("Sources", isDirectory: true)
        try FileManager.default.createDirectory(at: nested, withIntermediateDirectories: true)
        try write("root = true\n[*]\nindent_style = space\nindent_size = 4\n",
                  to: root.appendingPathComponent(".editorconfig"))
        try write("[*]\nindent_size = 2\n",
                  to: nested.appendingPathComponent(".editorconfig"))

        let file = nested.appendingPathComponent("main.swift")
        let settings = EditorConfigService.settings(for: file, workspaceRoot: root)

        XCTAssertEqual(settings.indentStyle, .space)
        XCTAssertEqual(settings.indentWidth, 2)
    }

    func testRootTrueStopsLookupAboveTheMarkedDirectory() throws {
        let outer = try makeTemporaryDirectory()
        let inner = outer.appendingPathComponent("project", isDirectory: true)
        try FileManager.default.createDirectory(at: inner, withIntermediateDirectories: true)
        try write("root = true\n[*]\nindent_style = tab\n", to: outer.appendingPathComponent(".editorconfig"))

        let settings = EditorConfigService.candidateDirectories(from: inner, upTo: nil)

        XCTAssertEqual(settings.count, 2)
        XCTAssertEqual(settings.map(\.lastPathComponent), ["project", outer.lastPathComponent])
    }

    func testIndentSizeTabFallsBackToTabWidth() {
        var settings = EditorConfigService.Settings()
        settings.indentSizeIsTab = true
        settings.indentSize = nil
        settings.tabWidth = 8

        XCTAssertEqual(settings.indentWidth, 8)
        XCTAssertEqual(settings.usesSpacesForIndentation, nil)
    }

    func testSettingsForMissingFileAreEmpty() {
        XCTAssertEqual(EditorConfigService.settings(for: nil, workspaceRoot: nil), EditorConfigService.Settings())
    }
}
