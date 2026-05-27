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

    init() {
        let defaults = UserDefaults.standard
        self.fontSize = CGFloat(defaults.double(forKey: Keys.fontSize).nonZero ?? 13)
        self.fontName = defaults.string(forKey: Keys.fontName) ?? "SF Mono"
        self.tabWidth = defaults.integer(forKey: Keys.tabWidth).nonZero ?? 4
        self.usesSpacesForTabs = defaults.object(forKey: Keys.usesSpacesForTabs) as? Bool ?? true
    }

    var editorTheme: EditorTheme {
        var theme = EditorTheme.default
        theme.fontSize = fontSize
        theme.fontName = fontName
        theme.tabWidth = tabWidth
        theme.usesSpacesForTabs = usesSpacesForTabs
        return theme
    }

    private func persist() {
        let defaults = UserDefaults.standard
        defaults.set(Double(fontSize), forKey: Keys.fontSize)
        defaults.set(fontName, forKey: Keys.fontName)
        defaults.set(tabWidth, forKey: Keys.tabWidth)
        defaults.set(usesSpacesForTabs, forKey: Keys.usesSpacesForTabs)
    }

    private enum Keys {
        static let fontSize = "editor.fontSize"
        static let fontName = "editor.fontName"
        static let tabWidth = "editor.tabWidth"
        static let usesSpacesForTabs = "editor.usesSpacesForTabs"
    }
}

private extension Double {
    var nonZero: Double? { self == 0 ? nil : self }
}

private extension Int {
    var nonZero: Int? { self == 0 ? nil : self }
}
