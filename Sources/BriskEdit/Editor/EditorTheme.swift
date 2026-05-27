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
    var tabWidth: Int
    var usesSpacesForTabs: Bool

    var nsFont: NSFont {
        NSFont(name: fontName, size: fontSize) ?? .monospacedSystemFont(ofSize: fontSize, weight: .regular)
    }

    var paragraphStyle: NSParagraphStyle {
        let style = NSMutableParagraphStyle()
        style.lineHeightMultiple = 1.2
        style.defaultTabInterval = nsFont.maximumAdvancement.width * CGFloat(tabWidth)
        style.tabStops = []
        return style
    }

    static let `default` = EditorTheme(
        fontSize: 13,
        fontName: "SF Mono",
        background: NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
                ? NSColor(white: 0.11, alpha: 1)
                : NSColor(white: 0.99, alpha: 1)
        },
        foreground: NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
                ? NSColor(white: 0.92, alpha: 1)
                : NSColor(white: 0.10, alpha: 1)
        },
        cursor: .controlAccentColor,
        selection: NSColor.selectedTextBackgroundColor.withAlphaComponent(0.55),
        gutterBackground: NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
                ? NSColor(white: 0.09, alpha: 1)
                : NSColor(white: 0.96, alpha: 1)
        },
        gutterForeground: NSColor.secondaryLabelColor,
        currentLineHighlight: NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
                ? NSColor(white: 1, alpha: 0.04)
                : NSColor(white: 0, alpha: 0.04)
        },
        tabWidth: 4,
        usesSpacesForTabs: true
    )
}
