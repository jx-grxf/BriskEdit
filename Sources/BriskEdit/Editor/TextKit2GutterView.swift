import AppKit

/// A TextKit 2-native line-number gutter. Unlike `LineNumberRulerView`
/// (`NSRulerView`, which blanks the TextKit 2 text view — see the project
/// notes), this is a plain sibling view placed left of the scroll view. It only
/// *reads* the text view's `NSTextLayoutManager` to position numbers, git
/// markers, and diagnostics; it never mutates the text view's layout or
/// geometry, so it can't blank the editor.
final class TextKit2GutterView: NSView {
    weak var textView: NSTextView?
    private var theme: EditorTheme
    private var gitDiff: GitDiff?
    private var diagnostics: [Int: Diagnostic.Severity] = [:]

    /// Fixed width — enough for ~5 digits at typical code sizes.
    static let width: CGFloat = 48

    init(theme: EditorTheme) {
        self.theme = theme
        super.init(frame: .zero)
        wantsLayer = true
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    override var isFlipped: Bool { true }

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

    // MARK: - Drawing

    override func draw(_ dirtyRect: NSRect) {
        theme.gutterBackground.setFill()
        dirtyRect.fill()

        guard let textView, let tlm = textView.textLayoutManager else { return }
        let inset = textView.textContainerInset.height
        let visible = textView.visibleRect
        guard visible.height > 0 else { return }

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
            drawGutterLine(line, font: numberFont, y: y, lineHeight: firstLineHeight)
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

        // Diagnostic dot on the leading edge.
        if let severity = diagnostics[line] {
            (severity == .error ? NSColor.systemRed : NSColor.systemYellow).setFill()
            let r: CGFloat = 6
            NSBezierPath(ovalIn: NSRect(x: 4, y: y + (lineHeight - r) / 2, width: r, height: r)).fill()
        }

        drawNumber(line, font: font, y: y, lineHeight: lineHeight)
    }

    private func drawNumber(_ line: Int, font: NSFont, y: CGFloat, lineHeight: CGFloat) {
        let attributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: theme.gutterForeground
        ]
        let string = NSAttributedString(string: "\(line)", attributes: attributes)
        let size = string.size()
        let x = bounds.width - size.width - 8
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
