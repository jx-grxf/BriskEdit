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

    /// How aggressively BriskEdit spends CPU/GPU/battery on the "live" editor
    /// features (minimap, hover, animations, and — as wiring lands — highlight
    /// and git-diff cadence). `adaptive` is the default and follows the system.
    enum PerformanceMode: String, CaseIterable, Identifiable {
        case lowPower
        case adaptive
        case power

        var id: String { rawValue }

        var title: String {
            switch self {
            case .lowPower: "Low Power"
            case .adaptive: "Adaptive"
            case .power: "Power"
            }
        }

        var systemImage: String {
            switch self {
            case .lowPower: "leaf"
            case .adaptive: "gauge.with.dots.needle.50percent"
            case .power: "bolt.fill"
            }
        }

        var explanation: String {
            switch self {
            case .lowPower:
                "Saves battery and CPU: hides the minimap, eases off hover docs and calms animations. Best on battery or when editing very large files."
            case .adaptive:
                "Default. Runs at full speed on power, and automatically eases off when macOS Low Power Mode is on or the Mac is under thermal pressure."
            case .power:
                "Everything immediate: minimap, hover documentation and full animations stay on regardless of power state. Also indexes syntax in the background so even the first open of a file is instantly highlighted. Best when plugged in."
            }
        }
    }

    /// The concrete knobs a resolved performance mode turns on or off.
    struct PerformanceProfile {
        let allowsMinimap: Bool
        let allowsHover: Bool
        let reduceMotion: Bool
        let highlightDebounce: TimeInterval
        let gitDiffDebounce: TimeInterval
        let markdownPreviewDebounceMilliseconds: Int

        init(mode: PerformanceMode) {
            switch mode {
            case .lowPower, .adaptive:
                allowsMinimap = false
                allowsHover = false
                reduceMotion = true
                highlightDebounce = 0.18
                gitDiffDebounce = 0.8
                markdownPreviewDebounceMilliseconds = 450
            case .power:
                allowsMinimap = true
                allowsHover = true
                reduceMotion = false
                highlightDebounce = 0.08
                gitDiffDebounce = 0.4
                markdownPreviewDebounceMilliseconds = 180
            }
        }
    }

    var performanceMode: PerformanceMode {
        didSet { persist() }
    }
    /// Live system signals the `adaptive` mode reacts to. Kept observable so
    /// views reading the effective profile re-render when power/thermal changes.
    private(set) var isLowPowerModeActive: Bool = ProcessInfo.processInfo.isLowPowerModeEnabled
    private(set) var thermalState: ProcessInfo.ThermalState = ProcessInfo.processInfo.thermalState

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
    /// Show the minimap (a zoomed-out overview) at the right edge of
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
    /// as Rich Presence. Off by default; opt-in per machine.
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
    /// Whether the first-run onboarding has been completed. Replaying it from
    /// Settings ▸ General flips this back to false so it shows again.
    var hasCompletedOnboarding: Bool {
        didSet { persist() }
    }
    /// Inline git blame: a faint author/commit label at the end of the caret's
    /// line. On by default; the headline Source Control nicety.
    var showInlineGitBlame: Bool {
        didSet { persist() }
    }
    /// Master switch for all source-control UI (the Source Control sidebar pane,
    /// gutter change bars and inline blame). On by default; users who don't work
    /// in a repo can turn the whole thing off in onboarding or settings.
    var sourceControlEnabled: Bool {
        didSet { persist() }
    }

    init() {
        let defaults = UserDefaults.standard
        self.startupBehavior = StartupBehavior(rawValue: defaults.string(forKey: Keys.startupBehavior) ?? "") ?? .restoreLastWorkspace
        self.performanceMode = PerformanceMode(rawValue: defaults.string(forKey: Keys.performanceMode) ?? "") ?? .adaptive
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
        self.hasCompletedOnboarding = defaults.bool(forKey: Keys.hasCompletedOnboarding)
        self.showInlineGitBlame = defaults.object(forKey: Keys.showInlineGitBlame) as? Bool ?? true
        self.sourceControlEnabled = defaults.object(forKey: Keys.sourceControlEnabled) as? Bool ?? true
        DiscordPresenceController.shared.configure(enabled: discordRichPresence)
        observeSystemPowerState()
    }

    /// Watches macOS Low Power Mode and thermal-pressure changes so `adaptive`
    /// re-resolves live (views reading the effective profile re-render).
    private func observeSystemPowerState() {
        let center = NotificationCenter.default
        center.addObserver(forName: .NSProcessInfoPowerStateDidChange, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.refreshSystemPowerState() }
        }
        center.addObserver(forName: ProcessInfo.thermalStateDidChangeNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.refreshSystemPowerState() }
        }
    }

    private func refreshSystemPowerState() {
        isLowPowerModeActive = ProcessInfo.processInfo.isLowPowerModeEnabled
        thermalState = ProcessInfo.processInfo.thermalState
    }

    /// The mode actually in effect: explicit modes pass through; `adaptive`
    /// drops to Low Power under OS Low Power Mode or serious thermal pressure.
    var resolvedPerformanceMode: PerformanceMode {
        guard performanceMode == .adaptive else { return performanceMode }
        if isLowPowerModeActive || thermalState == .serious || thermalState == .critical {
            return .lowPower
        }
        return .power
    }

    var performanceProfile: PerformanceProfile {
        PerformanceProfile(mode: resolvedPerformanceMode)
    }

    /// Whether to proactively pre-compile syntax grammars in the background.
    /// Only the explicit **Power** mode opts in — Adaptive and Low Power compile
    /// lazily on first open to avoid spending energy speculatively.
    var performsBackgroundIndexing: Bool { performanceMode == .power }

    /// Minimap shown only when the user enabled it *and* the active profile
    /// allows it — so Low Power hides it without losing the user's preference.
    var effectiveShowMinimap: Bool { showMinimap && performanceProfile.allowsMinimap }
    var effectiveShowHoverTooltips: Bool { showHoverTooltips && performanceProfile.allowsHover }
    var reduceMotion: Bool { performanceProfile.reduceMotion }
    var highlightDebounce: TimeInterval { performanceProfile.highlightDebounce }
    var gitDiffDebounce: TimeInterval { performanceProfile.gitDiffDebounce }
    var markdownPreviewDebounceMilliseconds: Int { performanceProfile.markdownPreviewDebounceMilliseconds }

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

    /// Gutter change bars / inline blame respect both their own toggle and the
    /// source-control master switch, so turning source control off hides
    /// everything without losing the individual preferences.
    var effectiveShowGitGutter: Bool { sourceControlEnabled && showGitGutter }
    var effectiveShowInlineGitBlame: Bool { sourceControlEnabled && showInlineGitBlame }

    var editorTheme: EditorTheme {
        let palette = ThemeStore.shared.theme(id: themeID) ?? .systemDefault
        return EditorTheme.make(
            palette: palette,
            fontSize: fontSize,
            fontName: fontName,
            tabWidth: tabWidth,
            usesSpacesForTabs: usesSpacesForTabs,
            showGitGutter: effectiveShowGitGutter,
            showCodeFolding: showCodeFolding
        )
    }

    private func persist() {
        let defaults = UserDefaults.standard
        defaults.set(startupBehavior.rawValue, forKey: Keys.startupBehavior)
        defaults.set(performanceMode.rawValue, forKey: Keys.performanceMode)
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
        defaults.set(hasCompletedOnboarding, forKey: Keys.hasCompletedOnboarding)
        defaults.set(showInlineGitBlame, forKey: Keys.showInlineGitBlame)
        defaults.set(sourceControlEnabled, forKey: Keys.sourceControlEnabled)
    }

    private enum Keys {
        static let startupBehavior = "app.startupBehavior"
        static let performanceMode = "app.performanceMode"
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
        static let hasCompletedOnboarding = "app.hasCompletedOnboarding"
        static let showInlineGitBlame = "editor.showInlineGitBlame"
        static let sourceControlEnabled = "editor.sourceControlEnabled"
    }
}

private extension Double {
    var nonZero: Double? { self == 0 ? nil : self }
}

private extension Int {
    var nonZero: Int? { self == 0 ? nil : self }
}
