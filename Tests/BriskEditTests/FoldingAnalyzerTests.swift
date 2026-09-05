import XCTest
@testable import BriskEdit

final class FoldingAnalyzerTests: XCTestCase {
    func testManyIndependentAllmanFunctionsKeepDistinctHeaders() {
        let count = 16_000
        let source = String(repeating: "void f()\n{\n x;\n}\n", count: count) as NSString
        let regions = FoldingAnalyzer.regions(in: source, tabWidth: 4)
        XCTAssertEqual(regions.count, count)
        XCTAssertEqual(regions.last?.headerLine, (count - 1) * 4)
        XCTAssertEqual(regions.last?.lastLine, count * 4 - 1)
    }

    func testNestedRegionsAndBlankLinesPreserveBoundaries() {
        let source = "outer\n  inner\n    body\n\n  sibling\nend\n" as NSString
        let regions = FoldingAnalyzer.regions(in: source, tabWidth: 4)
        XCTAssertEqual(regions.map(\.headerLine), [0, 1])
        XCTAssertEqual(regions.map(\.lastLine), [4, 2])
        XCTAssertEqual(source.substring(with: regions[0].hiddenRange), "  inner\n    body\n\n  sibling\n")
    }

    func testRefreshPolicyRecomputesForFoldingInputs() {
        var disabled = EditorTheme.default
        disabled.showCodeFolding = false
        var enabled = disabled
        enabled.showCodeFolding = true

        XCTAssertTrue(FoldingRefreshPolicy.needsRecompute(
            previousTheme: disabled,
            theme: enabled,
            languageChanged: false,
            documentReseeded: false
        ))

        var widerTabs = enabled
        widerTabs.tabWidth = 8
        XCTAssertTrue(FoldingRefreshPolicy.needsRecompute(
            previousTheme: enabled,
            theme: widerTabs,
            languageChanged: false,
            documentReseeded: false
        ))
        XCTAssertTrue(FoldingRefreshPolicy.needsRecompute(
            previousTheme: enabled,
            theme: enabled,
            languageChanged: true,
            documentReseeded: false
        ))
        XCTAssertTrue(FoldingRefreshPolicy.needsRecompute(
            previousTheme: enabled,
            theme: enabled,
            languageChanged: false,
            documentReseeded: true
        ))
    }

    func testRefreshPolicyIgnoresUnrelatedThemeChanges() {
        let previous = EditorTheme.default
        var changed = previous
        changed.fontSize += 1

        XCTAssertFalse(FoldingRefreshPolicy.needsRecompute(
            previousTheme: previous,
            theme: changed,
            languageChanged: false,
            documentReseeded: false
        ))
    }

    /// Allman-style brace block: the fold header should be promoted to the
    /// signature line and the trailing `}` absorbed, so the whole function
    /// collapses to a single clean header line.
    func testPromotesHeaderAndAbsorbsClosingBrace() {
        let source = """
        void shiftRowLeft(int table[ROWS][COLS], int row)
        {
            int temp = table[row][0];
            table[row][0] = temp;
        }
        """ as NSString

        let regions = FoldingAnalyzer.regions(in: source, tabWidth: 4)

        XCTAssertEqual(regions.count, 1)
        let region = try? XCTUnwrap(regions.first)
        // Header is the signature line (0-based 0), not the bare `{` on line 1.
        XCTAssertEqual(region?.headerLine, 0)
        // Last line is the closing brace (0-based 4), absorbed into the region.
        XCTAssertEqual(region?.lastLine, 4)
    }

    /// K&R brace style (`{` on the signature line) folds from the signature line
    /// and still absorbs the trailing closing brace.
    func testKAndRStyleAbsorbsClosingBrace() {
        let source = """
        int main(void) {
            int x = 1;
            return x;
        }
        """ as NSString

        let regions = FoldingAnalyzer.regions(in: source, tabWidth: 4)

        XCTAssertEqual(regions.count, 1)
        XCTAssertEqual(regions.first?.headerLine, 0)
        XCTAssertEqual(regions.first?.lastLine, 3)
    }
}
