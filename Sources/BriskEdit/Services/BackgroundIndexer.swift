import Foundation

/// Proactively warms expensive editor machinery — currently tree-sitter grammar
/// compilation (the Swift highlights query alone costs ~1.5s) — in the
/// background so that even the very first open of a file is instantly
/// highlighted instead of briefly showing the cheap regex pass.
///
/// This is a **Power-mode** perk: Adaptive and Low Power compile lazily on first
/// open instead, so they never spend energy speculatively. The warm-up runs one
/// grammar at a time at low priority (see `TreeSitterHighlighter.warmUp`), so the
/// indexing itself never makes the UI stutter.
@MainActor
enum BackgroundIndexer {
    private static var didWarmGrammars = false

    /// Starts background indexing if the user is in explicit Power mode. Safe to
    /// call repeatedly (on window appear or when the mode changes) — the grammar
    /// warm-up runs at most once per session.
    static func startIfEnabled(_ preferences: Preferences) {
        guard preferences.performsBackgroundIndexing else { return }
        guard !didWarmGrammars else { return }
        didWarmGrammars = true
        TreeSitterHighlighter.warmUp()
    }
}
