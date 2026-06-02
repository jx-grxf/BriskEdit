import AppKit

/// A TextKit 2-native line-number gutter. Unlike `LineNumberRulerView`
/// (`NSRulerView`, which blanks the TextKit 2 text view — see the project
/// notes), this is a plain sibling view placed left of the scroll view. It only
/// *reads* the text view's `NSTextLayoutManager` to position numbers, git
/// markers, and diagnostics; it never mutates the text view's layout or
/// geometry, so it can't blank the editor.
final class TextKit2GutterView: NSView {
    weak var textView: NSTextView?
    /// Code-folding state (foldable regions + which are collapsed). The gutter
    /// draws a chevron on each header line and toggles on click.
    weak var folding: FoldingController?
    /// Called after a fold toggles, so the host can re-apply syntax highlighting
    /// (the relayout drops rendering attributes).
    var onFoldToggled: (() -> Void)?
    private var theme: EditorTheme
    private var gitDiff: GitDiff?
    private var diagnostics: [Int: Diagnostic.Severity] = [:]
    /// Clickable chevron rects captured during the last draw, keyed by 1-based line.
    private var foldHitRects: [(line: Int, rect: NSRect)] = []

    /// Fixed width — enough for ~5 digits at typical code sizes, plus a small
    /// leading column for the diagnostic dot so it never touches the numbers.
    static let width: CGFloat = 48

    init(theme: EditorTheme) {
        self.theme = theme
        super.init(frame: .zero)
        wantsLayer = true
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    override var isFlipped: Bool { true }

    /// Repaint whenever Auto Layout (re)positions the gutter. The scroll view
    /// reaches its real size a layout pass *after* the editor first appears
    /// (tab switch, restored session); without this hook the gutter could draw
    /// once against a zero-height viewport and never get asked to redraw.
    override func layout() {
        super.layout()
        needsDisplay = true
    }

    // MARK: - Inputs

    func setTheme(_ theme: EditorTheme) {
        self.theme = theme
        needsDisplay = true
    }

    func setGitDiff(_ diff: GitDiff?) {
        gitDiff = diff
        needsDisplay = true
    }

    func setDiagnostics(_ diagnostics: [Diagnostic]) {
        // Collapse to the worst severity per line.
        var byLine: [Int: Diagnostic.Severity] = [:]
        for d in diagnostics {
            if let existing = byLine[d.line], existing.rank >= d.severity.rank { continue }
            byLine[d.line] = d.severity
        }
        self.diagnostics = byLine
        needsDisplay = true
    }

    func refresh() { needsDisplay = true }

    // MARK: - Fold interaction

    override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        guard let hit = foldHitRects.first(where: { $0.rect.contains(point) }), let folding else {
            super.mouseDown(with: event)
            return
        }
        folding.toggle(headerLine: hit.line - 1)
        onFoldToggled?()
        needsDisplay = true
    }

    // MARK: - Drawing

    override func draw(_ dirtyRect: NSRect) {
        theme.gutterBackground.setFill()
        dirtyRect.fill()
        foldHitRects.removeAll(keepingCapacity: true)

        guard let textView, let tlm = textView.textLayoutManager else { return }
        let inset = textView.textContainerInset.height
        let visible = textView.visibleRect
        // The viewport can momentarily report zero height *mid-relayout* (a tab
        // becoming visible, a restored session, the window activating). Painting
        // now would commit a blank gutter — and because nothing re-marks us for
        // display afterwards, it would stay blank until the next unrelated edit
        // or scroll. So when we're attached to a window but the viewport isn't
        // measured yet, skip this paint and ask for another once layout settles
        // instead of leaving an empty gutter behind.
        guard visible.height > 0 else {
            if window != nil {
                DispatchQueue.main.async { [weak self] in self?.needsDisplay = true }
            }
            return
        }

        let nsString = textView.string as NSString
        let numberFont = NSFont.monospacedDigitSystemFont(ofSize: max(9, theme.fontSize - 1), weight: .regular)

        // Find the first fragment intersecting the top of the visible rect, and
        // the 1-based line number it starts on.
        let topPoint = CGPoint(x: 0, y: max(visible.minY, 0))
        guard let startFragment = tlm.textLayoutFragment(for: topPoint) else {
            // Empty document: still show line 1.
            drawGutterLine(1, font: numberFont, y: inset - visible.minY, lineHeight: numberFont.boundingRectForFont.height)
            return
        }
        let startLocation = tlm.offset(from: tlm.documentRange.location, to: startFragment.rangeInElement.location)
        var line = lineIndex(in: nsString, upTo: startLocation) + 1

        var lastFragment: NSTextLayoutFragment?

        tlm.enumerateTextLayoutFragments(from: startFragment.rangeInElement.location, options: [.ensuresLayout]) { fragment in
            let frame = fragment.layoutFragmentFrame
            if frame.minY > visible.maxY { return false }
            let y = frame.minY + inset - visible.minY
            let firstLineHeight = fragment.textLineFragments.first?.typographicBounds.height ?? frame.height
            // Folded-away lines collapse to ~0 height; numbering them would stack
            // unreadable digits on top of each other. Skip them — the next visible
            // line carries the correct number.
            if folding?.isHidden(lineIndex0: line - 1) != true {
                drawGutterLine(line, font: numberFont, y: y, lineHeight: firstLineHeight)
            }
            lastFragment = fragment
            line += 1
            return true
        }

        // A document ending in a newline has a trailing empty line that the user
        // sees (and the cursor sits on after pressing Return at EOF). TextKit 2
        // tacks it on as an extra `textLineFragment` *inside* the last layout
        // fragment rather than as its own fragment, so the loop above never
        // numbers it. Position it from that extra line fragment's own bounds —
        // not the layout fragment's maxY, which would land a full line too low.
        if nsString.length > 0, nsString.character(at: nsString.length - 1) == unichar(0x0A),
           let lastFragment, lastFragment.textLineFragments.count >= 2,
           let trailing = lastFragment.textLineFragments.last {
            let originY = lastFragment.layoutFragmentFrame.minY + trailing.typographicBounds.minY
            let y = originY + inset - visible.minY
            if y <= visible.maxY {
                drawGutterLine(line, font: numberFont, y: y, lineHeight: trailing.typographicBounds.height)
            }
        }
    }

    /// Draws one gutter row: git change bar (trailing edge), diagnostic dot
    /// (leading edge) and the line number.
    private func drawGutterLine(_ line: Int, font: NSFont, y: CGFloat, lineHeight: CGFloat) {
        // Git change bar on the trailing edge — sized to the glyph line (not the
        // full fragment height, which includes line spacing and would overshoot
        // the visible text row).
        if theme.showGitGutter {
            if let kind = gitDiff?.lineKinds[line] {
                (kind == .added ? theme.gitAdded : theme.gitModified).setFill()
                NSRect(x: bounds.width - 3, y: y, width: 3, height: lineHeight).fill()
            }
            if gitDiff?.deletions.contains(line) == true {
                theme.gitDeleted.setFill()
                NSRect(x: bounds.width - 3, y: y, width: 3, height: 2).fill()
            }
        }

        // Diagnostic dot in its own leading column, kept clear of the numbers.
        if let severity = diagnostics[line] {
            (severity == .error ? NSColor.systemRed : NSColor.systemYellow).setFill()
            let r: CGFloat = 5
            NSBezierPath(ovalIn: NSRect(x: 2, y: y + (lineHeight - r) / 2, width: r, height: r)).fill()
        }

        drawNumber(line, font: font, y: y, lineHeight: lineHeight)
        drawFoldChevron(line, y: y, lineHeight: lineHeight)
    }

    /// Fold chevron on the inner (text-facing) edge for lines that head a
    /// foldable region: a down-triangle when expanded, a right-triangle when
    /// collapsed. Its rect is recorded for click hit-testing.
    private func drawFoldChevron(_ line: Int, y: CGFloat, lineHeight: CGFloat) {
        guard theme.showCodeFolding, let folding, folding.region(forHeaderLine: line - 1) != nil else { return }
        let folded = folding.isFolded(headerLine: line - 1)
        let box = NSRect(x: bounds.width - 11, y: y, width: 9, height: lineHeight)
        foldHitRects.append((line: line, rect: box))

        let s: CGFloat = 7
        let cx = box.midX
        let cy = box.midY
        let path = NSBezierPath()
        if folded { // ▶ points right
            path.move(to: NSPoint(x: cx - s / 3, y: cy - s / 2))
            path.line(to: NSPoint(x: cx + s / 2, y: cy))
            path.line(to: NSPoint(x: cx - s / 3, y: cy + s / 2))
        } else {    // ▼ points down
            path.move(to: NSPoint(x: cx - s / 2, y: cy - s / 3))
            path.line(to: NSPoint(x: cx + s / 2, y: cy - s / 3))
            path.line(to: NSPoint(x: cx, y: cy + s / 2))
        }
        path.close()
        theme.gutterForeground.setFill()
        path.fill()
    }

    private func drawNumber(_ line: Int, font: NSFont, y: CGFloat, lineHeight: CGFloat) {
        let attributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: theme.gutterForeground
        ]
        let string = NSAttributedString(string: "\(line)", attributes: attributes)
        let size = string.size()
        // Leave a slim column on the inner edge for the fold chevron — kept tight
        // so the numbers sit close to the code rather than floating far left.
        let x = bounds.width - size.width - 11
        let centeredY = y + max(0, (lineHeight - size.height) / 2)
        string.draw(at: CGPoint(x: x, y: centeredY))
    }

    /// 0-based line index of `location`, which always sits on a paragraph
    /// boundary (a layout-fragment start). Equals the number of lines fully
    /// contained in `[0, location)`.
    private func lineIndex(in string: NSString, upTo location: Int) -> Int {
        let end = min(location, string.length)
        guard end > 0 else { return 0 }
        var count = 0
        string.enumerateSubstrings(in: NSRange(location: 0, length: end), options: [.byLines, .substringNotRequired]) { _, _, _, _ in
            count += 1
        }
        return count
    }
}

private extension Diagnostic.Severity {
    var rank: Int {
        switch self {
        case .error: 3
        case .warning: 2
        case .note: 1
        }
    }
}
