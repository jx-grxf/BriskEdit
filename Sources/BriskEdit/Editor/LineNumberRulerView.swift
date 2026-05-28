import AppKit

final class LineNumberRulerView: NSRulerView {
    private weak var codeTextView: NSTextView?
    private var theme: EditorTheme
    private var lineStartOffsets: [Int] = [0]

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
        rebuildLineIndex()
        updateRuleThickness()
    }

    @available(*, unavailable)
    required init(coder: NSCoder) { fatalError("init(coder:) not implemented") }

    func setTheme(_ theme: EditorTheme) {
        self.theme = theme
        updateRuleThickness()
        needsDisplay = true
    }

    func invalidateLineNumbers() {
        rebuildLineIndex()
        updateRuleThickness()
        needsDisplay = true
    }

    @objc private func textDidChange(_ note: Notification) {
        rebuildLineIndex()
        updateRuleThickness()
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
            let scrollView = textView.enclosingScrollView
        else { return }

        let visibleRect = scrollView.contentView.bounds
        let textContainerOrigin = textView.textContainerOrigin
        let font = NSFont.monospacedDigitSystemFont(ofSize: theme.fontSize - 1, weight: .regular)
        let labelAttrs: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: theme.gutterForeground
        ]

        let visibleInContainer = NSRect(
            x: visibleRect.minX,
            y: visibleRect.minY - textContainerOrigin.y,
            width: visibleRect.width,
            height: visibleRect.height
        )

        textLayoutManager.enumerateTextLayoutFragments(
            from: textLayoutManager.documentRange.location,
            options: [.ensuresLayout]
        ) { fragment in
            let frame = fragment.layoutFragmentFrame
            if frame.maxY < visibleInContainer.minY { return true }
            if frame.minY > visibleInContainer.maxY { return false }

            let fragmentStart = fragment.rangeInElement.location
            let charOffset = textLayoutManager.textContentManager?.offset(
                from: textLayoutManager.documentRange.location,
                to: fragmentStart
            ) ?? 0
            var lineNumber = self.lineNumber(forCharacterOffset: charOffset)

            for lineFragment in fragment.textLineFragments {
                let isFirstLineOfFragment = lineFragment.characterRange.location == 0
                if isFirstLineOfFragment {
                    let bounds = lineFragment.typographicBounds
                    let yInContainer = frame.minY + bounds.minY
                    let yInView = yInContainer + textContainerOrigin.y - visibleRect.minY
                    let label = NSAttributedString(string: "\(lineNumber)", attributes: labelAttrs)
                    let labelSize = label.size()
                    label.draw(at: NSPoint(
                        x: self.ruleThickness - labelSize.width - 6,
                        y: yInView + (bounds.height - labelSize.height) / 2
                    ))
                }
                if let storage = (textLayoutManager.textContentManager as? NSTextContentStorage)?.textStorage {
                    let substringRange = NSRange(
                        location: charOffset + lineFragment.characterRange.location,
                        length: lineFragment.characterRange.length
                    )
                    if NSMaxRange(substringRange) <= storage.length {
                        let slice = (storage.string as NSString).substring(with: substringRange) as NSString
                        lineNumber += slice.components(separatedBy: "\n").count - 1
                    }
                }
            }
            return true
        }
    }

    private func rebuildLineIndex() {
        guard let text = codeTextView?.string else {
            lineStartOffsets = [0]
            return
        }
        var starts = [0]
        let nsString = text as NSString
        nsString.enumerateSubstrings(
            in: NSRange(location: 0, length: nsString.length),
            options: [.byLines, .substringNotRequired]
        ) { _, _, enclosingRange, _ in
            let next = NSMaxRange(enclosingRange)
            if next < nsString.length {
                starts.append(next)
            }
        }
        lineStartOffsets = starts
    }

    private func updateRuleThickness() {
        let digits = max(2, String(max(1, lineStartOffsets.count)).count)
        let font = NSFont.monospacedDigitSystemFont(ofSize: theme.fontSize - 1, weight: .regular)
        let sample = String(repeating: "8", count: digits) as NSString
        let width = sample.size(withAttributes: [.font: font]).width
        ruleThickness = max(44, ceil(width + 18))
    }

    private func lineNumber(forCharacterOffset offset: Int) -> Int {
        var low = 0
        var high = lineStartOffsets.count
        while low < high {
            let mid = (low + high) / 2
            if lineStartOffsets[mid] <= offset {
                low = mid + 1
            } else {
                high = mid
            }
        }
        return max(1, low)
    }
}
