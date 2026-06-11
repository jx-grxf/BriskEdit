import AppKit
import XCTest
@testable import BriskEdit

final class ImageViewerLayoutTests: XCTestCase {
    func testFitMagnificationKeepsWideImageInsideSplitPane() {
        let zoom = ImageViewerLayout.fitMagnification(
            imageSize: NSSize(width: 1920, height: 1080),
            viewportSize: NSSize(width: 400, height: 700)
        )

        XCTAssertEqual(zoom, 400 / 1920, accuracy: 0.0001)
    }

    func testFitMagnificationUsesHeightForTallImage() {
        let zoom = ImageViewerLayout.fitMagnification(
            imageSize: NSSize(width: 800, height: 1600),
            viewportSize: NSSize(width: 600, height: 400)
        )

        XCTAssertEqual(zoom, 0.25, accuracy: 0.0001)
    }

    func testFitMagnificationRespectsLimits() {
        XCTAssertEqual(
            ImageViewerLayout.fitMagnification(
                imageSize: NSSize(width: 10, height: 10),
                viewportSize: NSSize(width: 1000, height: 1000)
            ),
            8
        )
        XCTAssertEqual(
            ImageViewerLayout.fitMagnification(
                imageSize: NSSize(width: 100_000, height: 100_000),
                viewportSize: NSSize(width: 100, height: 100),
                minimum: 0.01
            ),
            0.01
        )
    }
}
