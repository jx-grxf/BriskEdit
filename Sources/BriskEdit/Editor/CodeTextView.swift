import AppKit

final class CodeTextView: NSTextView {
    var theme: EditorTheme = .default {
        didSet { applyTheme() }
    }

    static func makeScrollable(theme: EditorTheme) -> (scrollView: NSScrollView, textView: CodeTextView, ruler: LineNumberRulerView) {
        let contentStorage = NSTextContentStorage()
        let layoutManager = NSTextLayoutManager()
        contentStorage.addTextLayoutManager(layoutManager)

        let container = NSTextContainer(size: NSSize(width: 0, height: CGFloat.greatestFiniteMagnitude))
        container.widthTracksTextView = true
        container.lineFragmentPadding = 6
        layoutManager.textContainer = container

        let textView = CodeTextView(frame: .zero, textContainer: container)
        textView.minSize = NSSize(width: 0, height: 0)
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]

        textView.isRichText = false
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
        textView.textContainerInset = NSSize(width: 4, height: 8)

        let scrollView = NSScrollView()
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true
        scrollView.borderType = .noBorder
        scrollView.documentView = textView

        let ruler = LineNumberRulerView(textView: textView, theme: theme)
        scrollView.verticalRulerView = ruler
        scrollView.hasVerticalRuler = true
        scrollView.rulersVisible = true

        textView.theme = theme
        return (scrollView, textView, ruler)
    }

    private func applyTheme() {
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
        needsDisplay = true
    }

    override func insertTab(_ sender: Any?) {
        if theme.usesSpacesForTabs {
            let spaces = String(repeating: " ", count: theme.tabWidth)
            insertText(spaces, replacementRange: selectedRange())
        } else {
            super.insertTab(sender)
        }
    }

    override var defaultParagraphStyle: NSParagraphStyle? {
        get { theme.paragraphStyle }
        set { super.defaultParagraphStyle = newValue }
    }
}
