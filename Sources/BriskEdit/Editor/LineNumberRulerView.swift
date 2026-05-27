import AppKit

final class LineNumberRulerView: NSRulerView {
    private weak var codeTextView: NSTextView?
    private var theme: EditorTheme

    init(textView: NSTextView, theme: EditorTheme) {
        self.codeTextView = textView
        self.theme = theme
        super.init(scrollView: textView.enclosingScrollView, orientation: .verticalRuler)
        clientView = textView
        ruleThickness = 48

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(textDidChange(_:)),
            name: NSText.didChangeNotification,
            object: textView
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(boundsDidChange(_:)),
            name: NSView.boundsDidChangeNotification,
            object: textView.enclosingScrollView?.contentView
        )
        if let clipView = textView.enclosingScrollView?.contentView {
            clipView.postsBoundsChangedNotifications = true
        }
    }

    @available(*, unavailable)
    required init(coder: NSCoder) { fatalError("init(coder:) not implemented") }

    func setTheme(_ theme: EditorTheme) {
        self.theme = theme
        needsDisplay = true
    }

    @objc private func textDidChange(_ note: Notification) {
        needsDisplay = true
    }

    @objc private func boundsDidChange(_ note: Notification) {
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        theme.gutterBackground.setFill()
        dirtyRect.fill()
        drawHashMarksAndLabels(in: dirtyRect)
    }

    override func drawHashMarksAndLabels(in rect: NSRect) {
        guard
            let textView = codeTextView,
            let textLayoutManager = textView.textLayoutManager,
            let textContentManager = textLayoutManager.textContentManager,
            let scrollView = textView.enclosingScrollView
        else { return }

        let visibleRect = scrollView.contentView.bounds
        let textContainerOrigin = textView.textContainerOrigin

        let font = NSFont.monospacedDigitSystemFont(ofSize: theme.fontSize - 1, weight: .regular)
        let labelAttrs: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: theme.gutterForeground
        ]

        // Count newlines from document start to a given location.
        let documentRange = textLayoutManager.documentRange
        guard let documentString = (textContentManager as? NSTextContentStorage)?.textStorage?.string else {
            return
        }
        let nsString = documentString as NSString

        textLayoutManager.enumerateTextLayoutFragments(
            from: textLayoutManager.documentRange.location,
            options: [.ensuresLayout]
        ) { fragment in
            let fragmentFrame = fragment.layoutFragmentFrame
            let fragmentBottomInView = fragmentFrame.maxY + textContainerOrigin.y
            let fragmentTopInView = fragmentFrame.minY + textContainerOrigin.y

            // Skip fragments above the visible region; stop when we go past it.
            if fragmentBottomInView < visibleRect.minY {
                return true
            }
            if fragmentTopInView > visibleRect.maxY {
                return false
            }

            // Compute starting line number for this fragment by counting newlines before it.
            let fragmentStart = fragment.rangeInElement.location
            let charOffset = textContentManager.offset(from: documentRange.location, to: fragmentStart)
            let leadingRange = NSRange(location: 0, length: charOffset)
            var lineNumber = 1
            if leadingRange.length > 0 {
                nsString.enumerateSubstrings(
                    in: leadingRange,
                    options: [.byLines, .substringNotRequired]
                ) { _, _, _, _ in
                    lineNumber += 1
                }
            }

            for lineFragment in fragment.textLineFragments {
                // Only label the first line fragment per logical line.
                let isFirst = lineFragment.characterRange.location == 0
                if isFirst {
                    let lineRectInFragment = lineFragment.typographicBounds
                    let yInView = fragmentFrame.minY + lineRectInFragment.minY + textContainerOrigin.y - visibleRect.minY
                    let label = NSAttributedString(string: "\(lineNumber)", attributes: labelAttrs)
                    let labelSize = label.size()
                    let drawPoint = NSPoint(
                        x: self.ruleThickness - labelSize.width - 6,
                        y: yInView + (lineRectInFragment.height - labelSize.height) / 2
                    )
                    label.draw(at: drawPoint)
                }

                let substringRange = NSRange(
                    location: charOffset + lineFragment.characterRange.location,
                    length: lineFragment.characterRange.length
                )
                if NSMaxRange(substringRange) <= nsString.length {
                    let lineString = nsString.substring(with: substringRange) as NSString
                    lineNumber += lineString.components(separatedBy: "\n").count - 1
                }
            }
            return true
        }
    }
}
