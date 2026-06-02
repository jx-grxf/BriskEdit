import AppKit
import XCTest
@testable import BriskEdit

final class VSCodeThemeImportTests: XCTestCase {

    // MARK: - Hex parsing

    func testHexStringParsesCommonForms() {
        XCTAssertEqual(NSColor(hexString: "#FF0000")?.hexString, "#FF0000")
        XCTAssertEqual(NSColor(hexString: "00FF00")?.hexString, "#00FF00")
        XCTAssertEqual(NSColor(hexString: "#f00")?.hexString, "#FF0000")          // #RGB expands
        XCTAssertNil(NSColor(hexString: "#ZZZ"))
        XCTAssertNil(NSColor(hexString: "nonsense"))
    }

    func testHexStringPreservesAlpha() {
        let c = NSColor(hexString: "#11223380")
        XCTAssertNotNil(c)
        XCTAssertEqual(c?.hexString, "#11223380")
    }

    // MARK: - JSONC cleanup

    func testStripJSONCRemovesCommentsAndTrailingCommas() {
        let input = """
        {
          // a line comment
          "name": "Test", /* block */
          "type": "dark",
          "colors": {
            "editor.background": "#101010", // url-like value should survive: http://x
          },
        }
        """
        let cleaned = VSCodeThemeImporter.stripJSONC(input)
        let obj = try? JSONSerialization.jsonObject(with: Data(cleaned.utf8)) as? [String: Any]
        XCTAssertNotNil(obj)
        XCTAssertEqual(obj?["name"] as? String, "Test")
        XCTAssertEqual((obj?["colors"] as? [String: Any])?["editor.background"] as? String, "#101010")
    }

    func testStripJSONCKeepsSlashesInsideStrings() {
        let input = #"{"url": "https://example.com/path"}"#
        let cleaned = VSCodeThemeImporter.stripJSONC(input)
        let obj = try? JSONSerialization.jsonObject(with: Data(cleaned.utf8)) as? [String: Any]
        XCTAssertEqual(obj?["url"] as? String, "https://example.com/path")
    }

    // MARK: - Theme import

    private let sampleTheme = """
    {
      // BriskEdit test fixture
      "name": "Sample Dark",
      "type": "dark",
      "colors": {
        "editor.background": "#1A1B26",
        "editor.foreground": "#A9B1D6",
        "editorCursor.foreground": "#C0CAF5",
        "editor.selectionBackground": "#28344A",
        "editorLineNumber.foreground": "#3B4261",
        "editorGutter.addedBackground": "#449DAB",
      },
      "tokenColors": [
        { "scope": "comment", "settings": { "foreground": "#565F89" } },
        { "scope": "keyword", "settings": { "foreground": "#BB9AF7" } },
        { "scope": "keyword.control", "settings": { "foreground": "#FF0000" } },
        { "scope": ["string", "string.quoted"], "settings": { "foreground": "#9ECE6A" } },
        { "scope": "constant.numeric", "settings": { "foreground": "#FF9E64" } },
        { "scope": "entity.name.function", "settings": { "foreground": "#7AA2F7" } },
        { "scope": "entity.name.type", "settings": { "foreground": "#2AC3DE" } }
      ]
    }
    """

    func testImportMapsWorkbenchAndTokenColors() throws {
        let theme = try VSCodeThemeImporter.theme(
            fromJSON: Data(sampleTheme.utf8), id: "imported.sample", fallbackName: "fallback"
        )
        XCTAssertEqual(theme.name, "Sample Dark")
        XCTAssertTrue(theme.isDark)
        XCTAssertFalse(theme.isBuiltIn)
        XCTAssertEqual(theme.background.hexString, "#1A1B26")
        XCTAssertEqual(theme.foreground.hexString, "#A9B1D6")
        XCTAssertEqual(theme.cursor.hexString, "#C0CAF5")
        XCTAssertEqual(theme.gutterForeground.hexString, "#3B4261")
        XCTAssertEqual(theme.gitAdded.hexString, "#449DAB")
        XCTAssertEqual(theme.comment.hexString, "#565F89")
        XCTAssertEqual(theme.string.hexString, "#9ECE6A")
        XCTAssertEqual(theme.number.hexString, "#FF9E64")
        XCTAssertEqual(theme.function.hexString, "#7AA2F7")
        XCTAssertEqual(theme.type.hexString, "#2AC3DE")
    }

    func testMoreSpecificScopeWins() throws {
        // keyword.control (#FF0000) is more specific than keyword (#BB9AF7).
        let theme = try VSCodeThemeImporter.theme(
            fromJSON: Data(sampleTheme.utf8), id: "x", fallbackName: "x"
        )
        XCTAssertEqual(theme.controlKeyword.hexString, "#FF0000")
        XCTAssertEqual(theme.keyword.hexString, "#BB9AF7")
    }

    func testFallbackNameUsedWhenMissing() throws {
        let json = ##"{"type":"light","colors":{"editor.background":"#FFFFFF"}}"##
        let theme = try VSCodeThemeImporter.theme(
            fromJSON: Data(json.utf8), id: "x", fallbackName: "My Theme"
        )
        XCTAssertEqual(theme.name, "My Theme")
        XCTAssertFalse(theme.isDark)
    }

    func testEmptyThemeThrows() {
        let json = #"{"name":"empty"}"#
        XCTAssertThrowsError(try VSCodeThemeImporter.theme(
            fromJSON: Data(json.utf8), id: "x", fallbackName: "x"
        ))
    }

    // MARK: - Codable round-trip

    func testColorThemeDataRoundTrip() throws {
        let original = try VSCodeThemeImporter.theme(
            fromJSON: Data(sampleTheme.utf8), id: "imported.sample", fallbackName: "x"
        )
        let data = try JSONEncoder().encode(ColorThemeData(original))
        let restored = try JSONDecoder().decode(ColorThemeData.self, from: data).theme
        XCTAssertEqual(restored.id, original.id)
        XCTAssertEqual(restored.name, original.name)
        XCTAssertEqual(restored.background.hexString, original.background.hexString)
        XCTAssertEqual(restored.function.hexString, original.function.hexString)
        XCTAssertFalse(restored.isBuiltIn)
    }

    @MainActor
    func testThemeStoreImportsPersistsAndDeletesTheme() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let source = directory.appendingPathComponent("Sample Dark.json")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try Data(sampleTheme.utf8).write(to: source)
        defer { try? FileManager.default.removeItem(at: directory) }

        let store = ThemeStore(directory: directory)
        let theme = try store.importTheme(from: source)

        XCTAssertEqual(theme.id, "imported.sample-dark")
        XCTAssertEqual(store.theme(id: theme.id)?.name, "Sample Dark")
        XCTAssertTrue(FileManager.default.fileExists(atPath: directory.appendingPathComponent(theme.id + ".json").path))

        let reloaded = ThemeStore(directory: directory)
        XCTAssertEqual(reloaded.theme(id: theme.id)?.background.hexString, "#1A1B26")

        reloaded.deleteTheme(id: theme.id)
        XCTAssertNil(reloaded.theme(id: theme.id))
        XCTAssertFalse(FileManager.default.fileExists(atPath: directory.appendingPathComponent(theme.id + ".json").path))
    }
}
