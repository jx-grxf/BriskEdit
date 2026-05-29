import AppKit

final class CodeTextView: NSTextView {
    private var lastAppliedAppearanceName: NSAppearance.Name?

    var theme: EditorTheme = .default {
        didSet {
            if oldValue != theme {
                applyTheme()
            }
        }
    }
    var language: SourceLanguage = .plainText {
        didSet {
            if oldValue != language {
                rehighlight()
            }
        }
    }

    static func makeScrollable(theme: EditorTheme) -> (scrollView: NSScrollView, textView: CodeTextView, ruler: LineNumberRulerView) {
        let storage = NSTextStorage()
        let layoutManager = NSLayoutManager()
        storage.addLayoutManager(layoutManager)

        let textContainer = NSTextContainer(size: NSSize(width: 0, height: CGFloat.greatestFiniteMagnitude))
        textContainer.widthTracksTextView = true
        textContainer.heightTracksTextView = false
        textContainer.lineFragmentPadding = 6
        layoutManager.addTextContainer(textContainer)

        let textView = CodeTextView(frame: .zero, textContainer: textContainer)

        textView.minSize = NSSize(width: 0, height: 0)
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        textView.textContainer?.widthTracksTextView = true
        textView.textContainer?.heightTracksTextView = false
        textView.textContainer?.lineFragmentPadding = 6

        textView.isRichText = false
        textView.importsGraphics = false
        textView.allowsUndo = true
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        textView.isAutomaticSpellingCorrectionEnabled = false
        textView.isAutomaticLinkDetectionEnabled = false
        textView.smartInsertDeleteEnabled = false
        textView.isContinuousSpellCheckingEnabled = false
        textView.isGrammarCheckingEnabled = false
        textView.usesFontPanel = false
        textView.usesFindBar = true
        textView.isIncrementalSearchingEnabled = true
        textView.usesAdaptiveColorMappingForDarkAppearance = true
        textView.textContainerInset = NSSize(width: 4, height: 8)
        textView.isEditable = true
        textView.isSelectable = true
        textView.drawsBackground = true

        let scrollView = NSScrollView()
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true
        scrollView.borderType = .noBorder
        scrollView.drawsBackground = true
        scrollView.backgroundColor = theme.background
        scrollView.documentView = textView

        let ruler = LineNumberRulerView(textView: textView, theme: theme)
        scrollView.verticalRulerView = ruler
        scrollView.hasVerticalRuler = true
        scrollView.rulersVisible = true

        textView.applyTheme()
        return (scrollView, textView, ruler)
    }

    func applyTheme() {
        applyBaseTheme()
        SyntaxHighlighter.apply(to: self, language: language, theme: theme)
        needsDisplay = true
    }

    func refreshAppearanceIfNeeded() {
        let currentName = effectiveAppearance.bestMatch(from: [.darkAqua, .aqua])
        guard currentName != lastAppliedAppearanceName else { return }
        applyTheme()
    }

    private func applyBaseTheme() {
        lastAppliedAppearanceName = effectiveAppearance.bestMatch(from: [.darkAqua, .aqua])
        let foreground = resolvedForegroundColor
        font = theme.nsFont
        backgroundColor = theme.background
        textColor = foreground
        insertionPointColor = theme.cursor
        selectedTextAttributes = [
            .backgroundColor: theme.selection,
            .foregroundColor: foreground
        ]
        typingAttributes = [
            .font: theme.nsFont,
            .foregroundColor: foreground,
            .paragraphStyle: theme.paragraphStyle
        ]
        defaultParagraphStyle = theme.paragraphStyle
        enclosingScrollView?.backgroundColor = theme.background
    }

    func replaceTextIfNeeded(_ newText: String) {
        guard string != newText else { return }
        let selected = selectedRange()
        string = newText
        let safeLocation = min(selected.location, (string as NSString).length)
        setSelectedRange(NSRange(location: safeLocation, length: 0))
        SyntaxHighlighter.apply(to: self, language: language, theme: theme)
        (enclosingScrollView?.verticalRulerView as? LineNumberRulerView)?.invalidateLineNumbers()
    }

    func rehighlight() {
        SyntaxHighlighter.apply(to: self, language: language, theme: theme)
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        drawVisiblePlainTextOverlay(in: dirtyRect)
    }

    override func insertTab(_ sender: Any?) {
        if theme.usesSpacesForTabs {
            let spaces = String(repeating: " ", count: theme.tabWidth)
            insertText(spaces, replacementRange: selectedRange())
        } else {
            super.insertTab(sender)
        }
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        refreshAppearanceIfNeeded()
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        updateTextContainerSize(width: bounds.width)
        // Window-attached appearance may differ from the placeholder one used
        // during makeNSView — re-apply so colors resolve correctly now.
        if window != nil { applyTheme() }
    }

    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        updateTextContainerSize(width: newSize.width)
    }

    private func updateTextContainerSize(width: CGFloat) {
        let containerWidth = max(1, width)
        guard textContainer?.containerSize.width != containerWidth else { return }
        textContainer?.containerSize = NSSize(width: containerWidth, height: CGFloat.greatestFiniteMagnitude)
        if let textContainer {
            layoutManager?.ensureLayout(for: textContainer)
        }
    }

    private func drawVisiblePlainTextOverlay(in dirtyRect: NSRect) {
        guard !string.isEmpty else { return }

        let nsString = string as NSString
        let font = theme.nsFont
        let paragraphStyle = theme.paragraphStyle.mutableCopy() as? NSMutableParagraphStyle ?? NSMutableParagraphStyle()
        paragraphStyle.lineBreakMode = .byClipping

        let lineHeight = ceil(font.ascender - font.descender + font.leading) * paragraphStyle.lineHeightMultiple
        let origin = NSPoint(
            x: textContainerOrigin.x + (textContainer?.lineFragmentPadding ?? 0),
            y: textContainerOrigin.y + textContainerInset.height
        )
        let visibleRect = bounds.intersection(dirtyRect.insetBy(dx: -2, dy: -lineHeight))
        let firstLine = max(0, Int(floor((visibleRect.minY - origin.y) / max(1, lineHeight))))
        let lastLine = max(firstLine, Int(ceil((visibleRect.maxY - origin.y) / max(1, lineHeight))))

        var currentLine = 0
        var drawnLine = false
        nsString.enumerateSubstrings(
            in: NSRange(location: 0, length: nsString.length),
            options: [.byLines, .substringNotRequired]
        ) { _, lineRange, _, stop in
            defer { currentLine += 1 }
            guard currentLine >= firstLine else { return }
            guard currentLine <= lastLine else {
                stop.pointee = true
                return
            }

            drawnLine = true
            let y = origin.y + CGFloat(currentLine) * lineHeight
            self.drawLine(range: lineRange, at: NSPoint(x: origin.x, y: y), paragraphStyle: paragraphStyle)
        }

        if !drawnLine, nsString.length == 0 {
            return
        }
    }

    private func drawLine(range: NSRange, at point: NSPoint, paragraphStyle: NSParagraphStyle) {
        let nsString = string as NSString
        guard range.location <= nsString.length else { return }

        let safeRange = NSRange(
            location: range.location,
            length: min(range.length, nsString.length - range.location)
        )
        let line = nsString.substring(with: safeRange) as NSString
        let attributes: [NSAttributedString.Key: Any] = [
            .font: theme.nsFont,
            .foregroundColor: resolvedForegroundColor,
            .paragraphStyle: paragraphStyle
        ]
        line.draw(at: point, withAttributes: attributes)
    }

    private var resolvedForegroundColor: NSColor {
        if let match = effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]), match == .darkAqua {
            NSColor(calibratedWhite: 0.92, alpha: 1)
        } else {
            NSColor(calibratedWhite: 0.10, alpha: 1)
        }
    }
}
