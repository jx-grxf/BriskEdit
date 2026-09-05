import AppKit
import XCTest
@testable import BriskEdit

final class FileTypeIconMappingTests: XCTestCase {
    func testLanguageMarksStayLegibleAtTabIconSize() {
        XCTAssertEqual(SourceLanguage.html.iconMonogram, "</>")
        for language in SourceLanguage.allCases {
            if let mark = language.iconMonogram {
                XCTAssertLessThanOrEqual(mark.count, 3, "\(language.rawValue) mark is too wide")
            } else {
                XCTAssertNotNil(NSImage(systemSymbolName: language.iconName, accessibilityDescription: nil),
                                "\(language.rawValue) uses an unavailable SF Symbol")
            }
        }
    }
}
