import XCTest
@testable import BriskEdit

final class ToolHealthServiceTests: XCTestCase {
    func testDescriptorIDsAreUnique() {
        let ids = ToolHealthService.descriptors.map(\.id)

        XCTAssertEqual(Set(ids).count, ids.count)
    }

    func testDescriptorsCoverCoreToolCategories() {
        let categories = Set(ToolHealthService.descriptors.map(\.category))

        XCTAssertTrue(categories.contains(.runner))
        XCTAssertTrue(categories.contains(.languageServer))
        XCTAssertTrue(categories.contains(.formatter))
    }

    func testDescriptorsIncludeMissionCriticalNativeTools() {
        let names = Set(ToolHealthService.descriptors.map(\.name))

        XCTAssertTrue(names.contains("clang"))
        XCTAssertTrue(names.contains("gcc"))
        XCTAssertTrue(names.contains("swift"))
        XCTAssertTrue(names.contains("java"))
        XCTAssertTrue(names.contains("javac"))
        XCTAssertTrue(names.contains("jdtls"))
        XCTAssertTrue(names.contains("sourcekit-lsp"))
        XCTAssertTrue(names.contains("clangd"))
    }
}
