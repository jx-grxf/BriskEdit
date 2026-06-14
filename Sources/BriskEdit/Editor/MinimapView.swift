import AppKit

/// Minimap: a zoomed-out overview of the whole document drawn as
/// small per-line word bars, with a translucent overlay marking the visible
/// region. Click or drag to scroll the editor. A standalone sibling view (like
/// the gutter) that only *reads* the text view — it never mutates the editor's
/// text or layout, so it can't reintroduce the highlight flicker.
final class MinimapView: NSView {
    static let width: CGFloat = 78

    weak var textView: NSTextView?
    weak var scrollView: NSScrollView?

    private var theme: EditorTheme
    /// Cached line lengths/word-runs so a scroll redraw doesn't re-scan the text.
    private var lines: [LineGlyphs] = []
    private var contentDirty = true

    private let lineHeight: CGFloat = 3.0
    private let lineGap: CGFloat = 1.0
    private let horizontalInset: CGFloat = 4.0
    private let maxColumns = 140

    init(theme: EditorTheme) {
        self.theme = theme
        super.init(frame: .zero)
        wantsLayer = true
        layer?.backgroundColor = theme.background.cgColor
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    func setTheme(_ theme: EditorTheme) {
        self.theme = theme
        layer?.backgroundColor = theme.background.cgColor
        contentDirty = true
        needsDisplay = true
    }

    /// The text changed — rebuild the cached line model on the next draw.
    func invalidateContent() {
        contentDirty = true
        needsDisplay = true
    }

    /// The viewport scrolled/resized — only the overlay moved.
    func refresh() {
        needsDisplay = true
    }

    override var isFlipped: Bool { true }
    override var isOpaque: Bool { true }

    // MARK: - Content model

    private struct Run { let start: Int; let length: Int }
    private struct LineGlyphs { let runs: [Run] }

    private func rebuildIfNeeded() {
        guard contentDirty else { return }
        contentDirty = false
        lines.removeAll(keepingCapacity: true)
        guard let text = textView?.string, text.utf16.count <= 2_000_000 else { return }
        let ns = text as NSString
        ns.enumerateSubstrings(in: NSRange(location: 0, length: ns.length), options: [.byLines]) { [maxColumns] line, _, _, _ in
            let chars = (line ?? "") as NSString
            var runs: [Run] = []
            var col = 0
            var runStart = -1
            let limit = min(chars.length, maxColumns)
            while col < limit {
                let isSpace = CharacterSet.whitespaces.contains(UnicodeScalar(chars.character(at: col)) ?? " ")
                if isSpace {
                    if runStart >= 0 { runs.append(Run(start: runStart, length: col - runStart)); runStart = -1 }
                } else if runStart < 0 {
                    runStart = col
                }
                col += 1
            }
            if runStart >= 0 { runs.append(Run(start: runStart, length: col - runStart)) }
            self.lines.append(LineGlyphs(runs: runs))
        }
    }

    // MARK: - Geometry

    /// Vertical pixels per source line in the minimap.
    private var rowHeight: CGFloat { lineHeight + lineGap }

    /// Total minimap height the document would occupy at full scale.
    private var documentHeight: CGFloat { CGFloat(lines.count) * rowHeight }

    /// How far the minimap is scrolled so the visible region tracks the editor.
    private func minimapOffset() -> CGFloat {
        let viewH = bounds.height
        let docH = documentHeight
        guard docH > viewH else { return 0 }
        return scrollFraction() * (docH - viewH)
    }

    /// 0…1 position of the editor's viewport within its scrollable content.
    private func scrollFraction() -> CGFloat {
        guard let scrollView else { return 0 }
        let visible = scrollView.contentView.bounds
        let contentH = (scrollView.documentView?.frame.height ?? visible.height)
        let scrollable = max(1, contentH - visible.height)
        return min(1, max(0, visible.origin.y / scrollable))
    }

    /// Average editor pixels per source line (averages wrapped rows in — good
    /// enough to place the overlay without a full layout walk).
    private func editorLineHeight() -> CGFloat {
        guard let contentH = scrollView?.documentView?.frame.height, !lines.isEmpty else {
            return theme.nsFont.boundingRectForFont.height * 1.25
        }
        return contentH / CGFloat(lines.count)
    }

    // MARK: - Drawing

    override func draw(_ dirtyRect: NSRect) {
        rebuildIfNeeded()
        theme.background.setFill()
        bounds.fill()
        guard !lines.isEmpty else { return }

        let offset = minimapOffset()
        let charW = max(0.5, (bounds.width - horizontalInset * 2) / CGFloat(maxColumns) * 4)
        let barColor = theme.foreground.withAlphaComponent(0.45)
        barColor.setFill()

        // Only paint rows that fall inside the visible minimap window.
        let first = max(0, Int((offset) / rowHeight))
        let last = min(lines.count - 1, Int((offset + bounds.height) / rowHeight) + 1)
        guard first <= last else { return }
        for i in first...last {
            let y = CGFloat(i) * rowHeight - offset
            for run in lines[i].runs {
                let x = horizontalInset + CGFloat(run.start) * charW
                let w = min(CGFloat(run.length) * charW, bounds.width - horizontalInset - x)
                guard w > 0 else { continue }
                NSRect(x: x, y: y, width: w, height: lineHeight).fill()
            }
        }

        drawViewportOverlay(offset: offset)
    }

    private func drawViewportOverlay(offset: CGFloat) {
        guard let scrollView else { return }
        let lineH = editorLineHeight()
        guard lineH > 0 else { return }
        let visible = scrollView.contentView.bounds
        let firstLine = visible.origin.y / lineH
        let lineSpan = visible.height / lineH
        let y = firstLine * rowHeight - offset
        let h = max(rowHeight, lineSpan * rowHeight)

        let overlay = NSRect(x: 0, y: y, width: bounds.width, height: h)
        theme.foreground.withAlphaComponent(0.10).setFill()
        overlay.fill()
        theme.foreground.withAlphaComponent(0.20).setStroke()
        let border = NSBezierPath(rect: overlay.insetBy(dx: 0.5, dy: 0.5))
        border.lineWidth = 1
        border.stroke()
    }

    // MARK: - Interaction

    override func mouseDown(with event: NSEvent) { scrollToEvent(event) }
    override func mouseDragged(with event: NSEvent) { scrollToEvent(event) }

    /// Centers the editor's viewport on the source line under the cursor.
    private func scrollToEvent(_ event: NSEvent) {
        guard let scrollView, !lines.isEmpty else { return }
        let point = convert(event.locationInWindow, from: nil)
        let offset = minimapOffset()
        let targetLine = (point.y + offset) / rowHeight
        let lineH = editorLineHeight()
        let viewportLines = scrollView.contentView.bounds.height / lineH
        let topLine = max(0, targetLine - viewportLines / 2)
        let targetY = topLine * lineH

        let clip = scrollView.contentView
        let maxY = max(0, (scrollView.documentView?.frame.height ?? 0) - clip.bounds.height)
        clip.scroll(to: NSPoint(x: 0, y: min(maxY, targetY)))
        scrollView.reflectScrolledClipView(clip)
        needsDisplay = true
    }
}
