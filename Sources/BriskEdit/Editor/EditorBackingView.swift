import AppKit

/// One native backdrop per editor viewport. TextKit, gutter and minimap remain
/// ordinary siblings above it; no blur or opacity is applied to their content.
final class EditorBackingView: NSView {
    private var theme: EditorTheme
    private var effectView: NSVisualEffectView?
    private var tintView: EditorTintView?

    var isVibrant: Bool { theme.vibrancy != .off }
    override var isOpaque: Bool { !isVibrant }

    init(theme: EditorTheme) {
        self.theme = theme
        super.init(frame: .zero)
        wantsLayer = true
        layerContentsRedrawPolicy = .onSetNeedsDisplay
        setTheme(theme)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    func setTheme(_ theme: EditorTheme) {
        self.theme = theme
        if isVibrant {
            if effectView == nil {
                let effect = NSVisualEffectView(frame: bounds)
                effect.autoresizingMask = [.width, .height]
                effect.material = .underWindowBackground
                effect.blendingMode = .behindWindow
                // Keep the preview visible while the Settings window is key.
                // Accessibility and Low Power disable the backdrop explicitly.
                effect.state = .active
                addSubview(effect, positioned: .below, relativeTo: subviews.first)
                effectView = effect

                let tint = EditorTintView(frame: bounds)
                tint.autoresizingMask = [.width, .height]
                addSubview(tint, positioned: .above, relativeTo: effect)
                tintView = tint
            }
        } else {
            tintView?.removeFromSuperview()
            effectView?.removeFromSuperview()
            tintView = nil
            effectView = nil
        }
        updateColors()
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        updateColors()
    }

    private func updateColors() {
        effectiveAppearance.performAsCurrentDrawingAppearance {
            let color = theme.background.withAlphaComponent(1)
            layer?.backgroundColor = (isVibrant ? NSColor.clear : color).cgColor
            // Imported dark themes must not get a light material merely because
            // the window follows the system's light appearance (and vice versa).
            if let rgb = color.usingColorSpace(.sRGB) {
                let brightness = 0.2126 * rgb.redComponent + 0.7152 * rgb.greenComponent + 0.0722 * rgb.blueComponent
                effectView?.appearance = NSAppearance(named: brightness < 0.5 ? .darkAqua : .aqua)
            }
            tintView?.color = color.withAlphaComponent(theme.vibrancy.tintOpacity)
        }
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        guard !isVibrant else { return }
        theme.background.withAlphaComponent(1).setFill()
        dirtyRect.fill()
    }
}

private final class EditorTintView: NSView {
    var color: NSColor = .clear {
        didSet { layer?.backgroundColor = color.cgColor }
    }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    override var isOpaque: Bool { false }
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
}
