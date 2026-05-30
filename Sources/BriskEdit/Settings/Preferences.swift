import Foundation
import Observation
import SwiftUI

@MainActor
@Observable
final class Preferences {
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
    /// Automatically write the buffer to disk ~1 s after the last edit. Off by
    /// default. Read straight from UserDefaults by `TextDocument`, so the key
    /// must stay in sync.
    var autosave: Bool {
        didSet { persist() }
    }

    init() {
        let defaults = UserDefaults.standard
        self.fontSize = CGFloat(defaults.double(forKey: Keys.fontSize).nonZero ?? 13)
        self.fontName = defaults.string(forKey: Keys.fontName) ?? "SF Mono"
        self.tabWidth = defaults.integer(forKey: Keys.tabWidth).nonZero ?? 4
        self.usesSpacesForTabs = defaults.object(forKey: Keys.usesSpacesForTabs) as? Bool ?? true
        self.formatOnSave = defaults.bool(forKey: Keys.formatOnSave)
        self.showGitGutter = defaults.object(forKey: Keys.showGitGutter) as? Bool ?? true
        self.autosave = defaults.bool(forKey: Keys.autosave)
    }

    var editorTheme: EditorTheme {
        var theme = EditorTheme.default
        theme.fontSize = fontSize
        theme.fontName = fontName
        theme.tabWidth = tabWidth
        theme.usesSpacesForTabs = usesSpacesForTabs
        theme.showGitGutter = showGitGutter
        return theme
    }

    private func persist() {
        let defaults = UserDefaults.standard
        defaults.set(Double(fontSize), forKey: Keys.fontSize)
        defaults.set(fontName, forKey: Keys.fontName)
        defaults.set(tabWidth, forKey: Keys.tabWidth)
        defaults.set(usesSpacesForTabs, forKey: Keys.usesSpacesForTabs)
        defaults.set(formatOnSave, forKey: Keys.formatOnSave)
        defaults.set(showGitGutter, forKey: Keys.showGitGutter)
        defaults.set(autosave, forKey: Keys.autosave)
    }

    private enum Keys {
        static let fontSize = "editor.fontSize"
        static let fontName = "editor.fontName"
        static let tabWidth = "editor.tabWidth"
        static let usesSpacesForTabs = "editor.usesSpacesForTabs"
        static let formatOnSave = "editor.formatOnSave"
        static let showGitGutter = "editor.showGitGutter"
        static let autosave = "editor.autosave"
    }
}

private extension Double {
    var nonZero: Double? { self == 0 ? nil : self }
}

private extension Int {
    var nonZero: Int? { self == 0 ? nil : self }
}
