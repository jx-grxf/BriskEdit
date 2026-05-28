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
        // Let AppKit create the TextKit 2 scroll/clip/text-container stack. The
        // inherited factory preserves the subclass and avoids a blank custom stack.
        let scrollView = CodeTextView.scrollablePlainDocumentContentTextView()
        guard let textView = scrollView.documentView as? CodeTextView else {
            preconditionFailure("Expected CodeTextView document view")
        }

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

        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true
        scrollView.borderType = .noBorder
        scrollView.drawsBackground = true
        scrollView.backgroundColor = theme.background

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
        font = theme.nsFont
        backgroundColor = theme.background
        textColor = theme.foreground
        insertionPointColor = theme.cursor
        selectedTextAttributes = [
            .backgroundColor: theme.selection,
            .foregroundColor: theme.foreground
        ]
        typingAttributes = [
            .font: theme.nsFont,
            .foregroundColor: theme.foreground,
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
        textLayoutManager?.textViewportLayoutController.layoutViewport()
    }
}
