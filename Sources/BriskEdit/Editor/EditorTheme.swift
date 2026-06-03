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
    /// Draw and enable code-folding chevrons in the gutter. User-toggleable.
    var showCodeFolding: Bool = true

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

    /// Builds a runtime theme by layering the per-user font/indent settings on
    /// top of a color palette.
    static func make(
        palette: ColorTheme,
        fontSize: CGFloat,
        fontName: String,
        tabWidth: Int,
        usesSpacesForTabs: Bool,
        showGitGutter: Bool,
        showCodeFolding: Bool
    ) -> EditorTheme {
        EditorTheme(
            fontSize: fontSize,
            fontName: fontName,
            background: palette.background,
            foreground: palette.foreground,
            cursor: palette.cursor,
            selection: palette.selection,
            gutterBackground: palette.gutterBackground,
            gutterForeground: palette.gutterForeground,
            currentLineHighlight: palette.currentLineHighlight,
            keyword: palette.keyword,
            controlKeyword: palette.controlKeyword,
            type: palette.type,
            function: palette.function,
            preprocessor: palette.preprocessor,
            string: palette.string,
            number: palette.number,
            comment: palette.comment,
            gitAdded: palette.gitAdded,
            gitModified: palette.gitModified,
            gitDeleted: palette.gitDeleted,
            tabWidth: tabWidth,
            usesSpacesForTabs: usesSpacesForTabs,
            showGitGutter: showGitGutter,
            showCodeFolding: showCodeFolding
        )
    }

    static let `default` = make(
        palette: .systemDefault,
        fontSize: 13,
        fontName: "SF Mono",
        tabWidth: 4,
        usesSpacesForTabs: true,
        showGitGutter: true,
        showCodeFolding: true
    )
}
