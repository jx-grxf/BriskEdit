import XCTest
@testable import BriskEdit

final class TreeSitterConfigCacheTests: XCTestCase {
    @MainActor
    func testCachedConfigurationIsInstantAfterPrepare() async throws {
        // Use the smaller JSON grammar to test cache semantics without making
        // the test depend on cold Swift-query compile time on shared CI hosts.
        let first = await TreeSitterHighlighter.prepareConfiguration(for: .json)
        XCTAssertNotNil(first, "JSON grammar should compile")

        let t = Date()
        let cached = TreeSitterHighlighter.cachedConfiguration(for: .json)
        let warmMs = Date().timeIntervalSince(t) * 1000
        XCTAssertNotNil(cached, "config must be cached after prepare")
        XCTAssertLessThan(warmMs, 5, "cached config lookup must be instant (was \(warmMs) ms)")
    }
}
