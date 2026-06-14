import AppKit

/// A named editor color palette. Built-ins ship with the app; users can import
/// VS Code `.json` color themes which are stored alongside them. Holds *only*
/// colors — font, tab width and the other per-user editor knobs live in
/// `Preferences` and are layered on top when an `EditorTheme` is built.
struct ColorTheme: Identifiable, Equatable, Sendable {
    let id: String
    var name: String
    var isDark: Bool
    /// Built-ins are code; imported themes round-trip through disk.
    var isBuiltIn: Bool = true

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

    /// A compact set of swatches for a settings/menu preview, in reading order.
    var previewSwatches: [NSColor] {
        [background, keyword, type, function, string, number, comment]
    }

    // MARK: - Color helpers

    static func hex(_ value: UInt32) -> NSColor {
        NSColor(
            srgbRed: CGFloat((value >> 16) & 0xFF) / 255,
            green: CGFloat((value >> 8) & 0xFF) / 255,
            blue: CGFloat(value & 0xFF) / 255,
            alpha: 1
        )
    }

    /// Picks a color depending on the effective appearance so a theme reads well
    /// in both light and dark mode. Used by the appearance-following built-ins.
    static func adaptive(dark: NSColor, light: NSColor) -> NSColor {
        NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? dark : light
        }
    }
}

// MARK: - Built-in themes

extension ColorTheme {
    /// The default appearance-following palette (VS Code "Dark+"/"Light+").
    static let systemDefault = ColorTheme(
        id: "system",
        name: "System",
        isDark: true,
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
        gitDeleted: adaptive(dark: hex(0xE5534B), light: hex(0xCF222E))
    )

    static let oneDark = ColorTheme(
        id: "one-dark", name: "One Dark", isDark: true,
        background: hex(0x282C34), foreground: hex(0xABB2BF), cursor: hex(0x528BFF),
        selection: hex(0x3E4451).withAlphaComponent(0.99),
        gutterBackground: hex(0x282C34), gutterForeground: hex(0x5C6370),
        currentLineHighlight: hex(0x2C313C),
        keyword: hex(0xC678DD), controlKeyword: hex(0xC678DD), type: hex(0xE5C07B),
        function: hex(0x61AFEF), preprocessor: hex(0xC678DD), string: hex(0x98C379),
        number: hex(0xD19A66), comment: hex(0x5C6370),
        gitAdded: hex(0x98C379), gitModified: hex(0x61AFEF), gitDeleted: hex(0xE06C75)
    )

    static let dracula = ColorTheme(
        id: "dracula", name: "Dracula", isDark: true,
        background: hex(0x282A36), foreground: hex(0xF8F8F2), cursor: hex(0xF8F8F0),
        selection: hex(0x44475A),
        gutterBackground: hex(0x282A36), gutterForeground: hex(0x6272A4),
        currentLineHighlight: hex(0x44475A).withAlphaComponent(0.45),
        keyword: hex(0xFF79C6), controlKeyword: hex(0xFF79C6), type: hex(0x8BE9FD),
        function: hex(0x50FA7B), preprocessor: hex(0xFF79C6), string: hex(0xF1FA8C),
        number: hex(0xBD93F9), comment: hex(0x6272A4),
        gitAdded: hex(0x50FA7B), gitModified: hex(0x8BE9FD), gitDeleted: hex(0xFF5555)
    )

    static let nord = ColorTheme(
        id: "nord", name: "Nord", isDark: true,
        background: hex(0x2E3440), foreground: hex(0xD8DEE9), cursor: hex(0xD8DEE9),
        selection: hex(0x434C5E),
        gutterBackground: hex(0x2E3440), gutterForeground: hex(0x4C566A),
        currentLineHighlight: hex(0x3B4252),
        keyword: hex(0x81A1C1), controlKeyword: hex(0x81A1C1), type: hex(0x8FBCBB),
        function: hex(0x88C0D0), preprocessor: hex(0x5E81AC), string: hex(0xA3BE8C),
        number: hex(0xB48EAD), comment: hex(0x616E88),
        gitAdded: hex(0xA3BE8C), gitModified: hex(0x88C0D0), gitDeleted: hex(0xBF616A)
    )

    static let solarizedDark = ColorTheme(
        id: "solarized-dark", name: "Solarized Dark", isDark: true,
        background: hex(0x002B36), foreground: hex(0x839496), cursor: hex(0x839496),
        selection: hex(0x073642),
        gutterBackground: hex(0x002B36), gutterForeground: hex(0x586E75),
        currentLineHighlight: hex(0x073642).withAlphaComponent(0.6),
        keyword: hex(0x859900), controlKeyword: hex(0xCB4B16), type: hex(0xB58900),
        function: hex(0x268BD2), preprocessor: hex(0xCB4B16), string: hex(0x2AA198),
        number: hex(0xD33682), comment: hex(0x586E75),
        gitAdded: hex(0x859900), gitModified: hex(0x268BD2), gitDeleted: hex(0xDC322F)
    )

    static let monokai = ColorTheme(
        id: "monokai", name: "Monokai", isDark: true,
        background: hex(0x272822), foreground: hex(0xF8F8F2), cursor: hex(0xF8F8F0),
        selection: hex(0x49483E),
        gutterBackground: hex(0x272822), gutterForeground: hex(0x90908A),
        currentLineHighlight: hex(0x3E3D32),
        keyword: hex(0xF92672), controlKeyword: hex(0xF92672), type: hex(0x66D9EF),
        function: hex(0xA6E22E), preprocessor: hex(0xF92672), string: hex(0xE6DB74),
        number: hex(0xAE81FF), comment: hex(0x75715E),
        gitAdded: hex(0xA6E22E), gitModified: hex(0x66D9EF), gitDeleted: hex(0xF92672)
    )

    static let githubLight = ColorTheme(
        id: "github-light", name: "GitHub Light", isDark: false,
        background: hex(0xFFFFFF), foreground: hex(0x24292E), cursor: hex(0x044289),
        selection: hex(0xC8E1FF),
        gutterBackground: hex(0xFFFFFF), gutterForeground: hex(0x959DA5),
        currentLineHighlight: hex(0xF6F8FA),
        keyword: hex(0xD73A49), controlKeyword: hex(0xD73A49), type: hex(0x6F42C1),
        function: hex(0x6F42C1), preprocessor: hex(0xD73A49), string: hex(0x032F62),
        number: hex(0x005CC5), comment: hex(0x6A737D),
        gitAdded: hex(0x22863A), gitModified: hex(0x0366D6), gitDeleted: hex(0xCB2431)
    )

    /// Order shown in the picker. System first, then dark, then light.
    static let builtIns: [ColorTheme] = [
        .systemDefault, .oneDark, .dracula, .nord, .solarizedDark, .monokai, .githubLight,
    ]
}
