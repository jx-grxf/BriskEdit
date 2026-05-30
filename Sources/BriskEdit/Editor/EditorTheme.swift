import AppKit
import SwiftUI

struct EditorTheme: Sendable, Equatable {
    var fontSize: CGFloat
    var fontName: String
    var background: NSColor
    var foreground: NSColor
    var cursor: NSColor
    var selection: NSColor
    var gutterBackground: NSColor
    var gutterForeground: NSColor
    var currentLineHighlight: NSColor
    var keyword: NSColor
    var controlKeyword: NSColor
    var type: NSColor
    var function: NSColor
    var preprocessor: NSColor
    var string: NSColor
    var number: NSColor
    var comment: NSColor
    var gitAdded: NSColor
    var gitModified: NSColor
    var gitDeleted: NSColor
    var tabWidth: Int
    var usesSpacesForTabs: Bool
    /// Draw the green/orange/red git-change bars in the gutter. User-toggleable.
    var showGitGutter: Bool = true

    var nsFont: NSFont {
        NSFont(name: fontName, size: fontSize) ?? .monospacedSystemFont(ofSize: fontSize, weight: .regular)
    }

    var paragraphStyle: NSParagraphStyle {
        let style = NSMutableParagraphStyle()
        style.lineHeightMultiple = 1.25
        style.defaultTabInterval = nsFont.maximumAdvancement.width * CGFloat(tabWidth)
        style.tabStops = []
        return style
    }

    /// Picks a color depending on the effective appearance so the editor reads
    /// well in both light and dark mode. Dark values follow the VS Code "Dark+"
    /// palette; light values follow "Light+".
    private static func adaptive(dark: NSColor, light: NSColor) -> NSColor {
        NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? dark : light
        }
    }

    private static func hex(_ value: UInt32) -> NSColor {
        NSColor(
            srgbRed: CGFloat((value >> 16) & 0xFF) / 255,
            green: CGFloat((value >> 8) & 0xFF) / 255,
            blue: CGFloat(value & 0xFF) / 255,
            alpha: 1
        )
    }

    static let `default` = EditorTheme(
        fontSize: 13,
        fontName: "SF Mono",
        background: adaptive(dark: hex(0x1E1E1E), light: hex(0xFFFFFF)),
        foreground: adaptive(dark: hex(0xD4D4D4), light: hex(0x1F1F1F)),
        cursor: adaptive(dark: hex(0xAEAFAD), light: hex(0x005CC5)),
        selection: NSColor.selectedTextBackgroundColor.withAlphaComponent(0.50),
        gutterBackground: adaptive(dark: hex(0x1E1E1E), light: hex(0xFFFFFF)),
        gutterForeground: adaptive(dark: hex(0x6E7681), light: hex(0xB0B0B0)),
        currentLineHighlight: adaptive(dark: NSColor(white: 1, alpha: 0.05), light: NSColor(white: 0, alpha: 0.04)),
        keyword: adaptive(dark: hex(0x569CD6), light: hex(0x0000FF)),
        controlKeyword: adaptive(dark: hex(0xC586C0), light: hex(0xAF00DB)),
        type: adaptive(dark: hex(0x4EC9B0), light: hex(0x267F99)),
        function: adaptive(dark: hex(0xDCDCAA), light: hex(0x795E26)),
        preprocessor: adaptive(dark: hex(0xC586C0), light: hex(0xAF00DB)),
        string: adaptive(dark: hex(0xCE9178), light: hex(0xA31515)),
        number: adaptive(dark: hex(0xB5CEA8), light: hex(0x098658)),
        comment: adaptive(dark: hex(0x6A9955), light: hex(0x008000)),
        gitAdded: adaptive(dark: hex(0x4BB543), light: hex(0x2EA043)),
        gitModified: adaptive(dark: hex(0x4A9EFF), light: hex(0x0969DA)),
        gitDeleted: adaptive(dark: hex(0xE5534B), light: hex(0xCF222E)),
        tabWidth: 4,
        usesSpacesForTabs: true
    )
}
