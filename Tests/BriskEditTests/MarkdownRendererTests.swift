import XCTest
@testable import BriskEdit

final class MarkdownRendererTests: XCTestCase {
    func testRendererHandlesCommonBlocks() {
        let html = MarkdownRenderer.html(for: """
        # Title

        - one
        - two

        | Name | Value |
        | --- | --- |
        | BriskEdit | fast |

        ```swift
        print("hi")
        ```

        [site](https://example.com)
        ![alt](image.png)
        [[Code-Completion]]
        """)

        XCTAssertTrue(html.contains("<h1>Title</h1>"))
        XCTAssertTrue(html.contains("<ul><li>one</li><li>two</li></ul>"))
        XCTAssertTrue(html.contains("<table>"))
        XCTAssertTrue(html.contains("<pre><code class=\"language-swift\">print(&quot;hi&quot;)</code></pre>"))
        XCTAssertTrue(html.contains("<a href=\"https://example.com\">site</a>"))
        XCTAssertTrue(html.contains("<img src=\"image.png\" alt=\"alt\">"))
        XCTAssertTrue(html.contains("<a href=\"briskedit-wikilink://Code-Completion\">Code-Completion</a>"))
    }
}
