import AppKit
import SwiftUI

enum EditorVibrancy: String, CaseIterable, Identifiable, Sendable {
    case off, subtle, balanced, strong

    var id: String { rawValue }
    var title: String {
        switch self {
        case .off: "Off"
        case .subtle: "Subtle"
        case .balanced: "Balanced"
        case .strong: "Strong"
        }
    }

    /// Additional theme tint above the system's own frosted material. Strong
    /// must leave the native blur visible instead of covering it with dark paint.
    var tintOpacity: CGFloat {
        switch self {
        case .off: 1
        case .subtle: 0.60
        case .balanced: 0.36
        case .strong: 0.16
        }
    }

    func resolved(reduceTransparency: Bool, lowPower: Bool = false) -> Self {
        reduceTransparency || lowPower ? .off : self
    }
}

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
    var vibrancy: EditorVibrancy = .off

    /// Surface-only changes must not reconfigure TextKit or rebuild highlighting.
    func hasSameTextAppearance(as other: EditorTheme) -> Bool {
        var copy = self
        copy.vibrancy = other.vibrancy
        return copy == other
    }

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
        showCodeFolding: Bool,
        vibrancy: EditorVibrancy = .off
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
            showCodeFolding: showCodeFolding,
            vibrancy: vibrancy
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
