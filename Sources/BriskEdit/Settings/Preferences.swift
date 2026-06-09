import AppKit
import Foundation
import Observation
import SwiftUI

@MainActor
@Observable
final class Preferences {
    enum StartupBehavior: String, CaseIterable, Identifiable {
        case restoreLastWorkspace
        case startEmpty

        var id: String { rawValue }

        var title: String {
            switch self {
            case .restoreLastWorkspace: "Restore Last Workspace"
            case .startEmpty: "Start Empty"
            }
        }
    }

    var startupBehavior: StartupBehavior {
        didSet { persist() }
    }
    var fontSize: CGFloat {
        didSet { persist() }
    }
    var fontName: String {
        didSet { persist() }
    }
    var tabWidth: Int {
        didSet { persist() }
    }
    var usesSpacesForTabs: Bool {
        didSet { persist() }
    }
    /// Identifier of the selected color theme (see ColorTheme / ThemeStore).
    /// Falls back to the appearance-following system theme when unknown.
    var themeID: String {
        didSet { persist() }
    }
    /// Run an installed external formatter (clang-format, swift-format, gofmt,
    /// prettier, …) over the buffer right before each save. Off by default.
    var formatOnSave: Bool {
        didSet { persist() }
    }
    /// Show the git change bars (added/modified/deleted) in the editor gutter.
    /// On by default.
    var showGitGutter: Bool {
        didSet { persist() }
    }
    /// Show clickable code-folding chevrons in the editor gutter. On by default.
    var showCodeFolding: Bool {
        didSet { persist() }
    }
    /// Show the VS Code-style minimap (zoomed-out overview) at the right edge of
    /// the editor. On by default.
    var showMinimap: Bool {
        didSet { persist() }
    }
    /// Show LSP hover documentation popovers while the pointer rests on a symbol.
    /// On by default; can be noisy in dense code, so users can disable it.
    var showHoverTooltips: Bool {
        didSet { persist() }
    }
    /// Automatically write the buffer to disk ~1 s after the last edit. Off by
    /// default. Read straight from UserDefaults by `TextDocument`, so the key
    /// must stay in sync.
    var autosave: Bool {
        didSet { persist() }
    }
    /// Font used by the integrated terminal. Defaults to the Nerd Font most
    /// users set in Terminal.app so glyphs/powerline prompts render correctly.
    var terminalFontName: String {
        didSet { persist() }
    }
    var terminalFontSize: CGFloat {
        didSet { persist() }
    }
    /// When on, the terminal treats ⌥ (Option) as the Meta modifier (⌥-key sends
    /// ESC-key). Off by default so Option keeps producing layout characters —
    /// crucial on international layouts where `@`, `{`, `}`, `|`, `~` live on
    /// Option combinations (e.g. German ⌥L = `@`). Power users who want Emacs-style
    /// Meta can turn it on.
    var terminalOptionAsMeta: Bool {
        didSet { persist() }
    }
    /// Experimental: mirror the active file, language and workspace to Discord
    /// as Rich Presence (vscord-style). Off by default; opt-in per machine.
    var discordRichPresence: Bool {
        didSet {
            persist()
            DiscordPresenceController.shared.configure(enabled: discordRichPresence)
        }
    }
    /// Show the file name on the Discord card. When off, only the language is
    /// shown ("Editing a Swift file") — for private repos.
    var discordShowFileName: Bool {
        didSet { persist() }
    }
    /// Show the workspace/folder name on the Discord card.
    var discordShowWorkspace: Bool {
        didSet { persist() }
    }
    /// Show the live "elapsed" timer on the Discord card.
    var discordShowElapsed: Bool {
        didSet { persist() }
    }

    init() {
        let defaults = UserDefaults.standard
        self.startupBehavior = StartupBehavior(rawValue: defaults.string(forKey: Keys.startupBehavior) ?? "") ?? .restoreLastWorkspace
        self.fontSize = CGFloat(defaults.double(forKey: Keys.fontSize).nonZero ?? 13)
        self.fontName = defaults.string(forKey: Keys.fontName) ?? "SF Mono"
        self.tabWidth = defaults.integer(forKey: Keys.tabWidth).nonZero ?? 4
        self.usesSpacesForTabs = defaults.object(forKey: Keys.usesSpacesForTabs) as? Bool ?? true
        self.themeID = defaults.string(forKey: Keys.themeID) ?? "system"
        self.formatOnSave = defaults.bool(forKey: Keys.formatOnSave)
        self.showGitGutter = defaults.object(forKey: Keys.showGitGutter) as? Bool ?? true
        self.showCodeFolding = defaults.object(forKey: Keys.showCodeFolding) as? Bool ?? true
        self.showMinimap = defaults.object(forKey: Keys.showMinimap) as? Bool ?? true
        self.showHoverTooltips = defaults.object(forKey: Keys.showHoverTooltips) as? Bool ?? true
        self.autosave = defaults.bool(forKey: Keys.autosave)
        self.terminalFontName = defaults.string(forKey: Keys.terminalFontName) ?? "MesloLGS Nerd Font"
        self.terminalFontSize = CGFloat(defaults.double(forKey: Keys.terminalFontSize).nonZero ?? 14)
        self.terminalOptionAsMeta = defaults.object(forKey: Keys.terminalOptionAsMeta) as? Bool ?? false
        self.discordRichPresence = defaults.bool(forKey: Keys.discordRichPresence)
        self.discordShowFileName = defaults.object(forKey: Keys.discordShowFileName) as? Bool ?? true
        self.discordShowWorkspace = defaults.object(forKey: Keys.discordShowWorkspace) as? Bool ?? true
        self.discordShowElapsed = defaults.object(forKey: Keys.discordShowElapsed) as? Bool ?? true
        DiscordPresenceController.shared.configure(enabled: discordRichPresence)
    }

    /// Resolves the configured terminal font, falling back to the system
    /// monospaced face when the named font isn't installed. Accepts both
    /// PostScript names (`MesloLGSNerdFont-Regular`) and the family name shown
    /// in Terminal.app's profile (`MesloLGS Nerd Font`).
    var terminalFont: NSFont {
        Self.resolveFont(named: terminalFontName, size: terminalFontSize)
    }

    static func resolveFont(named name: String, size: CGFloat) -> NSFont {
        if let exact = NSFont(name: name, size: size) {
            return exact
        }
        // Terminal.app shows the *family* name; map it to the regular face.
        if let fromFamily = NSFontManager.shared.font(
            withFamily: name, traits: [], weight: 5, size: size
        ) {
            return fromFamily
        }
        return .monospacedSystemFont(ofSize: size, weight: .regular)
    }

    /// Adjusts the editor font size, clamped to the same range as the settings
    /// stepper. Used by the View ▸ Font Size menu commands.
    func adjustFontSize(by delta: CGFloat) {
        fontSize = min(28, max(9, fontSize + delta))
    }

    func resetFontSize() {
        fontSize = 13
    }

    var editorTheme: EditorTheme {
        let palette = ThemeStore.shared.theme(id: themeID) ?? .systemDefault
        return EditorTheme.make(
            palette: palette,
            fontSize: fontSize,
            fontName: fontName,
            tabWidth: tabWidth,
            usesSpacesForTabs: usesSpacesForTabs,
            showGitGutter: showGitGutter,
            showCodeFolding: showCodeFolding
        )
    }

    private func persist() {
        let defaults = UserDefaults.standard
        defaults.set(startupBehavior.rawValue, forKey: Keys.startupBehavior)
        defaults.set(Double(fontSize), forKey: Keys.fontSize)
        defaults.set(fontName, forKey: Keys.fontName)
        defaults.set(tabWidth, forKey: Keys.tabWidth)
        defaults.set(usesSpacesForTabs, forKey: Keys.usesSpacesForTabs)
        defaults.set(themeID, forKey: Keys.themeID)
        defaults.set(formatOnSave, forKey: Keys.formatOnSave)
        defaults.set(showGitGutter, forKey: Keys.showGitGutter)
        defaults.set(showCodeFolding, forKey: Keys.showCodeFolding)
        defaults.set(showMinimap, forKey: Keys.showMinimap)
        defaults.set(showHoverTooltips, forKey: Keys.showHoverTooltips)
        defaults.set(autosave, forKey: Keys.autosave)
        defaults.set(terminalFontName, forKey: Keys.terminalFontName)
        defaults.set(Double(terminalFontSize), forKey: Keys.terminalFontSize)
        defaults.set(terminalOptionAsMeta, forKey: Keys.terminalOptionAsMeta)
        defaults.set(discordRichPresence, forKey: Keys.discordRichPresence)
        defaults.set(discordShowFileName, forKey: Keys.discordShowFileName)
        defaults.set(discordShowWorkspace, forKey: Keys.discordShowWorkspace)
        defaults.set(discordShowElapsed, forKey: Keys.discordShowElapsed)
    }

    private enum Keys {
        static let startupBehavior = "app.startupBehavior"
        static let fontSize = "editor.fontSize"
        static let fontName = "editor.fontName"
        static let tabWidth = "editor.tabWidth"
        static let usesSpacesForTabs = "editor.usesSpacesForTabs"
        static let themeID = "editor.themeID"
        static let formatOnSave = "editor.formatOnSave"
        static let showGitGutter = "editor.showGitGutter"
        static let showCodeFolding = "editor.showCodeFolding"
        static let showMinimap = "editor.showMinimap"
        static let showHoverTooltips = "editor.showHoverTooltips"
        static let autosave = "editor.autosave"
        static let terminalFontName = "terminal.fontName"
        static let terminalFontSize = "terminal.fontSize"
        static let terminalOptionAsMeta = "terminal.optionAsMeta"
        static let discordRichPresence = "experimental.discordRichPresence"
        static let discordShowFileName = "experimental.discordShowFileName"
        static let discordShowWorkspace = "experimental.discordShowWorkspace"
        static let discordShowElapsed = "experimental.discordShowElapsed"
    }
}

private extension Double {
    var nonZero: Double? { self == 0 ? nil : self }
}

private extension Int {
    var nonZero: Int? { self == 0 ? nil : self }
}
