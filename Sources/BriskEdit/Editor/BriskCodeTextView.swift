import AppKit

/// NSTextView subclass that notifies the coordinator when it loses focus, so
/// the floating completion popup can be dismissed.
final class BriskCodeTextView: NSTextView {
    var onResignFirstResponder: (() -> Void)?
    var onBecomeFirstResponder: (() -> Void)?
    /// ⌘D — add the next occurrence of the selection as another cursor.
    var onSelectNextOccurrence: (() -> Void)?
    /// Go to definition for the symbol at a character index (⌘-click or F12).
    var onGoToDefinition: ((Int) -> Void)?
    var onFindReferences: ((Int) -> Void)?
    /// Mouse paused over a point (hover) / left the view.
    var onHover: ((NSPoint) -> Void)?
    var onHoverExit: (() -> Void)?
    /// Reformats the whole buffer with the language's external formatter
    /// (context menu / ⇧⌥F). Only offered when `canFormatDocument` is true.
    var onFormatDocument: (() -> Void)?
    var canFormatDocument: () -> Bool = { false }
    private var hoverTrackingArea: NSTrackingArea?

    /// Resolved diagnostic spans (character ranges) with severity, drawn as wavy
    /// underlines under the offending text — the red/yellow squiggle.
    private var diagnosticUnderlines: [(range: NSRange, severity: Diagnostic.Severity)] = []
    var diagnosticErrorColor: NSColor = .systemRed
    var diagnosticWarningColor: NSColor = .systemYellow

    func setDiagnosticUnderlines(_ underlines: [(range: NSRange, severity: Diagnostic.Severity)]) {
        diagnosticUnderlines = underlines
        needsDisplay = true
    }

    override var isOpaque: Bool { drawsBackground && backgroundColor.alphaComponent == 1 }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let hoverTrackingArea { removeTrackingArea(hoverTrackingArea) }
        let area = NSTrackingArea(rect: bounds, options: [.mouseMoved, .mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect], owner: self, userInfo: nil)
        addTrackingArea(area)
        hoverTrackingArea = area
    }

    override func mouseMoved(with event: NSEvent) {
        super.mouseMoved(with: event)
        onHover?(convert(event.locationInWindow, from: nil))
    }

    override func mouseExited(with event: NSEvent) {
        super.mouseExited(with: event)
        onHoverExit?()
    }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        if flags == .command, event.charactersIgnoringModifiers == "d" {
            onSelectNextOccurrence?()
            return true
        }
        // ⇧⌥F — Format Document.
        if !event.isARepeat,
           flags == [.shift, .option], event.charactersIgnoringModifiers?.lowercased() == "f",
           canFormatDocument() {
            onFormatDocument?()
            return true
        }
        return super.performKeyEquivalent(with: event)
    }

    override func menu(for event: NSEvent) -> NSMenu? {
        let menu = super.menu(for: event) ?? NSMenu()
        if onFindReferences != nil {
            let item = NSMenuItem(title: "Find References…", action: #selector(findReferencesAction), keyEquivalent: "")
            item.target = self
            menu.insertItem(item, at: 0)
        }
        if canFormatDocument() {
            let item = NSMenuItem(title: "Format Document", action: #selector(formatDocumentAction), keyEquivalent: "f")
            item.keyEquivalentModifierMask = [.shift, .option]
            item.target = self
            menu.insertItem(item, at: 0)
            menu.insertItem(.separator(), at: 1)
        }
        return menu
    }

    @objc private func findReferencesAction() {
        onFindReferences?(selectedRange().location)
    }

    @objc private func formatDocumentAction() {
        onFormatDocument?()
    }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 111 { // F12
            onGoToDefinition?(selectedRange().location)
            return
        }
        super.keyDown(with: event)
    }

    override func mouseDown(with event: NSEvent) {
        if event.modifierFlags.contains(.command) {
            let point = convert(event.locationInWindow, from: nil)
            onGoToDefinition?(characterIndexForInsertion(at: point))
            return
        }
        super.mouseDown(with: event)
    }

    override func resignFirstResponder() -> Bool {
        onResignFirstResponder?()
        return super.resignFirstResponder()
    }

    override func becomeFirstResponder() -> Bool {
        let became = super.becomeFirstResponder()
        if became { onBecomeFirstResponder?() }
        return became
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        drawDiagnosticUnderlines(in: dirtyRect)
    }

    /// Paints a wavy underline beneath every diagnostic span that intersects the
    /// dirty rect. Uses TextKit 2 segment enumeration so multi-line spans and
    /// wrapped lines each get their own squiggle, in the text's own coordinates
    /// (scrolls correctly, read-only — never touches layout).
    private func drawDiagnosticUnderlines(in dirtyRect: NSRect) {
        guard !diagnosticUnderlines.isEmpty,
              let layoutManager = textLayoutManager,
              let contentManager = layoutManager.textContentManager else { return }
        let documentStart = contentManager.documentRange.location
        let origin = textContainerOrigin
        let length = (string as NSString).length

        for underline in diagnosticUnderlines {
            let range = underline.range
            guard range.location >= 0, range.length > 0, NSMaxRange(range) <= length,
                  let start = contentManager.location(documentStart, offsetBy: range.location),
                  let end = contentManager.location(start, offsetBy: range.length),
                  let textRange = NSTextRange(location: start, end: end) else { continue }
            let color = underline.severity == .warning ? diagnosticWarningColor : diagnosticErrorColor
            layoutManager.enumerateTextSegments(in: textRange, type: .standard, options: []) { _, frame, _, _ in
                var rect = frame
                rect.origin.x += origin.x
                rect.origin.y += origin.y
                guard rect.width > 0, rect.intersects(dirtyRect) else { return true }
                Self.drawSquiggle(under: rect, color: color)
                return true
            }
        }
    }

    /// Draws a 2px-amplitude sine-ish squiggle along the bottom edge of `rect`.
    private static func drawSquiggle(under rect: NSRect, color: NSColor) {
        let amplitude: CGFloat = 1.4
        let wavelength: CGFloat = 4
        let baseline = rect.maxY - amplitude
        let path = NSBezierPath()
        path.lineWidth = 1
        path.move(to: NSPoint(x: rect.minX, y: baseline))
        var x = rect.minX
        var up = true
        while x < rect.maxX {
            let nextX = min(x + wavelength / 2, rect.maxX)
            let midX = (x + nextX) / 2
            let controlY = baseline + (up ? amplitude : -amplitude)
            path.curve(to: NSPoint(x: nextX, y: baseline),
                       controlPoint1: NSPoint(x: midX, y: controlY),
                       controlPoint2: NSPoint(x: midX, y: controlY))
            x = nextX
            up.toggle()
        }
        color.setStroke()
        path.stroke()
    }
}
