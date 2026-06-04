import SwiftUI

/// Shared design constants for BriskEdit's window chrome (tab strip, status bar,
/// sidebar headers). Centralizing spacing, heights and the status-bar type ramp
/// keeps the chrome uniform and makes it tunable from one place, instead of the
/// magic numbers that were scattered across the workspace views.
enum DesignTokens {
    /// Stack spacing and padding steps. Use these instead of inline literals so
    /// the chrome stays on a consistent rhythm.
    enum Spacing {
        static let xSmall: CGFloat = 4
        static let small: CGFloat = 6
        static let medium: CGFloat = 8
        static let large: CGFloat = 12
    }

    /// Fixed heights for the bars that frame the editor.
    enum Chrome {
        static let statusBarHeight: CGFloat = 22
        static let tabStripHeight: CGFloat = 32
        /// Upper bound for an elided file name in the tab/status chrome.
        static let labelMaxWidth: CGFloat = 220
    }

    /// The status bar's two-tier type ramp: the system caption for worded labels
    /// (file name, branch, language) — which reads as native macOS chrome — and a
    /// monospaced caption reserved for numbers (Ln/Col, file size) so digits stay
    /// aligned while typing.
    enum Typography {
        static let statusLabel: Font = .caption
        static let statusNumeric: Font = .caption.monospaced()
    }
}
