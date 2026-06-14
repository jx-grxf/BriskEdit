import XCTest
@testable import BriskEdit

final class TreeSitterConfigCacheTests: XCTestCase {
    @MainActor
    func testCachedConfigurationIsInstantAfterPrepare() async throws {
        // Compiling the Swift highlights query costs ~1.5s; it must happen once,
        // off the main thread. After that, the cached lookup that every open and
        // tab switch hits has to be effectively free.
        let first = await TreeSitterHighlighter.prepareConfiguration(for: .swift)
        XCTAssertNotNil(first, "Swift grammar should compile")

        let t = Date()
        let cached = TreeSitterHighlighter.cachedConfiguration(for: .swift)
        let warmMs = Date().timeIntervalSince(t) * 1000
        XCTAssertNotNil(cached, "config must be cached after prepare")
        XCTAssertLessThan(warmMs, 5, "cached config lookup must be instant (was \(warmMs) ms)")
    }
}
