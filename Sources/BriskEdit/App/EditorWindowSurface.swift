import AppKit

/// The window must permit transparency as well as its editor subviews. Keep
/// the original surface per window so another workspace is never affected.
@MainActor
final class EditorWindowSurface {
    private weak var window: NSWindow?
    private var original: (opaque: Bool, color: NSColor)?

    init(window: NSWindow) { self.window = window }

    func setVibrant(_ enabled: Bool) {
        guard let window else { return }
        if enabled {
            if original == nil { original = (window.isOpaque, window.backgroundColor) }
            if window.isOpaque { window.isOpaque = false }
            if window.backgroundColor.alphaComponent != 0 { window.backgroundColor = .clear }
        } else if let original {
            window.isOpaque = original.opaque
            window.backgroundColor = original.color
            self.original = nil
        }
    }
}
