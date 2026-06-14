import AppKit
import SwiftUI

private final class EditorBackingView: NSView {
    var fillColor: NSColor {
        didSet {
            layer?.backgroundColor = fillColor.cgColor
            needsDisplay = true
        }
    }

    init(fillColor: NSColor) {
        self.fillColor = fillColor
        super.init(frame: .zero)
        wantsLayer = true
        layer?.backgroundColor = fillColor.cgColor
        layerContentsRedrawPolicy = .onSetNeedsDisplay
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    override var isOpaque: Bool { true }

    override func draw(_ dirtyRect: NSRect) {
        fillColor.setFill()
        dirtyRect.fill()
    }
}

struct TextKit2EditorHost: NSViewRepresentable {
    @Bindable var document: TextDocument
    let theme: EditorTheme
    var showMinimap: Bool = true
    var showHoverTooltips: Bool = true
    var highlightDebounce: TimeInterval = 0.08
    var gitDiffDebounce: TimeInterval = 0.4
    var showInlineGitBlame: Bool = true
    var workspaceRootURL: URL?
    /// Opens a (possibly different) file at a 1-based line/column — used for
    /// go-to-definition. Provided by the host view, which owns the workspace.
    var onOpenLocation: ((URL, Int, Int) -> Void)?

    func makeNSView(context: Context) -> NSView {
        let textView = BriskCodeTextView(usingTextLayoutManager: true)
        textView.delegate = context.coordinator
        textView.string = document.text
        configure(textView, theme: theme)
        context.coordinator.textView = textView
        context.coordinator.document = document
        context.coordinator.theme = theme
        context.coordinator.isLargeFile = document.isLargeFile
        context.coordinator.showHoverTooltips = showHoverTooltips
        context.coordinator.highlightDebounce = highlightDebounce
        context.coordinator.gitDiffDebounce = gitDiffDebounce
        context.coordinator.showInlineBlame = showInlineGitBlame
        context.coordinator.workspaceRootURL = workspaceRootURL
        context.coordinator.installBlameLabel(in: textView)
        textView.onResignFirstResponder = { [weak coordinator = context.coordinator] in
            coordinator?.dismissCompletions()
        }
        // Returning to the editor (e.g. after committing in the terminal) should
        // refresh the gutter's git diff, which is otherwise stale.
        textView.onBecomeFirstResponder = { [weak coordinator = context.coordinator] in
            coordinator?.scheduleGitDiff()
        }
        textView.onSelectNextOccurrence = { [weak coordinator = context.coordinator] in
            coordinator?.selectNextOccurrence()
        }
        textView.onGoToDefinition = { [weak coordinator = context.coordinator] index in
            coordinator?.goToDefinition(at: index)
        }
        textView.onHover = { [weak coordinator = context.coordinator] point in
            coordinator?.scheduleHover(at: point)
        }
        textView.onHoverExit = { [weak coordinator = context.coordinator] in
            coordinator?.hideHover()
        }
        textView.canFormatDocument = { [weak coordinator = context.coordinator] in
            coordinator?.document.language.supportsFormatting ?? false
        }
        textView.onFormatDocument = { [weak coordinator = context.coordinator] in
            coordinator?.formatDocument()
        }
        context.coordinator.openLocation = onOpenLocation
        context.coordinator.configurePopup()

        let scrollView = NSScrollView()
        scrollView.borderType = .noBorder
        scrollView.drawsBackground = true
        scrollView.backgroundColor = theme.background
        scrollView.contentView.drawsBackground = true
        scrollView.contentView.backgroundColor = theme.background
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true
        // The editor has its own `textContainerInset` for top spacing and never
        // sits against the window title bar (it's below the tab strip), so it
        // doesn't want AppKit auto-managing title-bar/toolbar content insets.
        // NOTE: this does *not* fix the open-files tab strip vanishing on code
        // tabs — that's the macOS 26 scroll-edge effect pulling this scroll view
        // up under the bar, and is solved by pinning the strip as a
        // `.safeAreaInset` in EditorTabsView, not here.
        scrollView.automaticallyAdjustsContentInsets = false
        scrollView.documentView = textView

        textView.minSize = .zero
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        textView.isHorizontallyResizable = false
        textView.isVerticallyResizable = true
        textView.autoresizingMask = [.width]
        textView.textContainer?.widthTracksTextView = true
        textView.textContainer?.heightTracksTextView = false
        textView.textContainer?.containerSize = NSSize(width: scrollView.contentSize.width, height: CGFloat.greatestFiniteMagnitude)

        // TextKit 2-native gutter as a sibling left of the scroll view — never
        // an NSRulerView (which blanks the text). See TextKit2GutterView.
        let gutter = TextKit2GutterView(theme: theme)
        gutter.textView = textView
        context.coordinator.gutter = gutter
        context.coordinator.scrollView = scrollView

        // Code folding: a content-storage delegate collapses folded lines
        // (display-only, never mutates the storage). The gutter draws/toggles
        // chevrons; toggling drops rendering attributes, so re-highlight after.
        let folding = context.coordinator.folding
        folding.contentStorage = textView.textContentStorage
        folding.textView = textView
        textView.textContentStorage?.delegate = folding
        gutter.folding = folding
        gutter.onFoldToggled = { [weak coordinator = context.coordinator] in
            coordinator?.forceHighlightRefresh()
            coordinator?.gutter?.refresh()
            coordinator?.minimap?.refresh()
        }

        // Zoomed-out overview on the right, a read-only sibling like the gutter.
        let minimap = MinimapView(theme: theme)
        minimap.textView = textView
        minimap.scrollView = scrollView
        context.coordinator.minimap = minimap

        let container = EditorBackingView(fillColor: theme.background)
        // Let SwiftUI own the container's frame (TAMIC = true, the AppKit
        // default — same as the PDF/QuickLook preview hosts). Keeping this
        // `false` left the container's *own* size undefined: its subviews are
        // pinned to its edges, but nothing constrains its height, so SwiftUI
        // measured it ambiguously and the editor overflowed upward — collapsing
        // the open-files tab strip to zero height. Only the subviews use
        // Auto Layout; they lay out inside whatever frame SwiftUI assigns.
        gutter.translatesAutoresizingMaskIntoConstraints = false
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        minimap.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(gutter)
        container.addSubview(scrollView)
        container.addSubview(minimap)
        let minimapVisible = showMinimap && !document.isLargeFile
        let minimapWidth = minimap.widthAnchor.constraint(equalToConstant: minimapVisible ? MinimapView.width : 0)
        context.coordinator.minimapWidthConstraint = minimapWidth
        minimap.isHidden = !minimapVisible
        NSLayoutConstraint.activate([
            gutter.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            gutter.topAnchor.constraint(equalTo: container.topAnchor),
            gutter.bottomAnchor.constraint(equalTo: container.bottomAnchor),
            gutter.widthAnchor.constraint(equalToConstant: TextKit2GutterView.width),
            scrollView.leadingAnchor.constraint(equalTo: gutter.trailingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: minimap.leadingAnchor),
            scrollView.topAnchor.constraint(equalTo: container.topAnchor),
            scrollView.bottomAnchor.constraint(equalTo: container.bottomAnchor),
            minimap.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            minimap.topAnchor.constraint(equalTo: container.topAnchor),
            minimap.bottomAnchor.constraint(equalTo: container.bottomAnchor),
            minimapWidth
        ])

        // Repaint the gutter as the text scrolls or the viewport resizes.
        scrollView.contentView.postsBoundsChangedNotifications = true
        context.coordinator.observeScroll(of: scrollView)

        context.coordinator.lastSyncedRevision = document.revision
        context.coordinator.lastLanguage = document.language
        context.coordinator.recomputeFoldRegions()
        context.coordinator.applyHighlight()
        context.coordinator.warmUpLSP()
        context.coordinator.scheduleGitDiff()
        DispatchQueue.main.async { [weak scrollView, weak textView, weak coordinator = context.coordinator] in
            scrollView?.window?.makeFirstResponder(textView)
            // Honor a navigation target set before the view existed (e.g. opened
            // from Find in Files / the symbol outline).
            coordinator?.applyPendingReveal()
        }
        return container
    }

    func updateNSView(_ container: NSView, context: Context) {
        guard let textView = context.coordinator.textView else { return }
        let coordinator = context.coordinator
        coordinator.document = document
        let largeFileModeChanged = coordinator.isLargeFile != document.isLargeFile
        coordinator.isLargeFile = document.isLargeFile
        coordinator.openLocation = onOpenLocation
        coordinator.workspaceRootURL = workspaceRootURL
        coordinator.showHoverTooltips = showHoverTooltips
        coordinator.highlightDebounce = highlightDebounce
        coordinator.gitDiffDebounce = gitDiffDebounce
        coordinator.updateInlineBlameEnabled(showInlineGitBlame)
        let previousTheme = coordinator.theme
        let themeChanged = previousTheme != theme
        coordinator.theme = theme

        // Re-applying the text view's static config (font, paragraph style,
        // container inset) forces a full TextKit 2 relayout. Running it on every
        // keystroke and cursor move made the viewport briefly mis-measure its
        // height and overscroll past the document end — the editor "jumped" and
        // line numbers slid off-screen. Only reconfigure when the theme actually
        // changed; everything `configure` sets is otherwise constant.
        if themeChanged {
            configure(textView, theme: theme)
            coordinator.scrollView?.backgroundColor = theme.background
            coordinator.scrollView?.contentView.backgroundColor = theme.background
            coordinator.gutter?.setTheme(theme)
            coordinator.minimap?.setTheme(theme)
            (container as? EditorBackingView)?.fillColor = theme.background
        }

        // Toggle the minimap without rebuilding the editor.
        if let minimap = coordinator.minimap, let width = coordinator.minimapWidthConstraint {
            let minimapVisible = showMinimap && !document.isLargeFile
            let target: CGFloat = minimapVisible ? MinimapView.width : 0
            if width.constant != target {
                width.constant = target
                minimap.isHidden = !minimapVisible
                if minimapVisible { minimap.invalidateContent() }
            }
        }

        if largeFileModeChanged, document.isLargeFile {
            coordinator.disableExpensiveFeaturesForLargeFile()
        }

        // Only touch the (potentially huge) text when the change came from
        // outside this editor — detected via the cheap revision counter rather
        // than comparing whole strings on every cursor move.
        var didReseed = false
        if document.revision != coordinator.lastSyncedRevision {
            let selection = textView.selectedRange()
            let newText = document.text
            textView.string = newText
            textView.setSelectedRange(NSRange(location: min(selection.location, (newText as NSString).length), length: 0))
            coordinator.lastSyncedRevision = document.revision
            coordinator.scheduleGitDiff()
            didReseed = true
        }
        // In-editor edits drive their own debounced re-highlight; only re-run it
        // here for an external re-seed, a theme switch, or a language change
        // (the user picked a different syntax in the status bar).
        let languageChanged = coordinator.lastLanguage != document.language
        coordinator.lastLanguage = document.language
        if FoldingRefreshPolicy.needsRecompute(
            previousTheme: previousTheme,
            theme: theme,
            languageChanged: languageChanged,
            documentReseeded: didReseed
        ) {
            coordinator.recomputeFoldRegions()
        }
        if didReseed || themeChanged || languageChanged || (largeFileModeChanged && !document.isLargeFile) {
            coordinator.applyHighlight()
        }
        coordinator.syncLSPIdentity()
        if didReseed {
            coordinator.minimap?.invalidateContent()
        }
        coordinator.gutter?.setDiagnostics(document.diagnostics)
        coordinator.refreshDiagnosticUnderlines()
        coordinator.applyPendingReveal()
    }

    /// Report the *proposed* size as our fitting size instead of letting
    /// SwiftUI fall back to the AppKit intrinsic/`fittingSize` measurement.
    /// The container hosts a vertically-resizable `NSTextView` whose height
    /// tracks the document's content, so its `fittingSize` is the full text
    /// height. Without this, SwiftUI reads that oversized height, over-subscribes
    /// the editor's row in the surrounding `VStack` and compresses the fixed-
    /// height open-files tab strip above it to zero. Returning the proposal makes
    /// the editor a fully flexible cell that fills whatever space SwiftUI grants,
    /// exactly like the simple PDF/QuickLook preview hosts. See the Brain note
    /// "Editor-ScrollView verschiebt Tab-Leiste".
    func sizeThatFits(_ proposal: ProposedViewSize, nsView: NSView, context: Context) -> CGSize? {
        proposal.replacingUnspecifiedDimensions()
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(document: document, theme: theme)
    }

    private func configure(_ textView: NSTextView, theme: EditorTheme) {
        textView.isEditable = true
        textView.isSelectable = true
        textView.isRichText = false
        textView.importsGraphics = false
        textView.allowsUndo = true
        textView.drawsBackground = true
        textView.backgroundColor = theme.background
        textView.textColor = theme.foreground
        textView.insertionPointColor = theme.cursor
        textView.font = theme.nsFont
        textView.defaultParagraphStyle = theme.paragraphStyle
        textView.selectedTextAttributes = [.backgroundColor: theme.selection]
        textView.typingAttributes = [
            .font: theme.nsFont,
            .foregroundColor: theme.foreground,
            .paragraphStyle: theme.paragraphStyle
        ]
        textView.textContainerInset = NSSize(width: 10, height: 12)
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        textView.isAutomaticSpellingCorrectionEnabled = false
        textView.smartInsertDeleteEnabled = false
        textView.usesFindBar = true
        textView.isIncrementalSearchingEnabled = true
    }

    @MainActor
    final class Coordinator: NSObject, NSTextViewDelegate {
        var document: TextDocument
        var theme: EditorTheme
        weak var textView: NSTextView?
        weak var gutter: TextKit2GutterView?
        weak var minimap: MinimapView?
        var minimapWidthConstraint: NSLayoutConstraint?
        weak var scrollView: NSScrollView?
        var workspaceRootURL: URL?
        private var highlightWork: DispatchWorkItem?
        private var gitWork: DispatchWorkItem?
        private var lspWork: DispatchWorkItem?
        private var minimapWork: DispatchWorkItem?
        private var lspItems: [LSPCompletion] = []
        private var lspDiagnosticsURI: String?
        private var lspLanguage: SourceLanguage?
        private var lspRoot: String?
        var lastSyncedRevision = 0
        private let popup = CompletionPopup()
        let folding = FoldingController()
        private let hoverPanel = HoverPanel()
        private var hoverWork: DispatchWorkItem?
        private let signaturePanel = SignatureHelpPanel()
        private var signatureWork: DispatchWorkItem?
        private var treeSitterHighlighter: TreeSitterHighlighter?
        private var treeSitterAttemptedLanguage: SourceLanguage?
        private var formatTask: Task<Void, Never>?
        private var hoverIndex = -1
        var showHoverTooltips = true
        var isLargeFile = false
        var highlightDebounce: TimeInterval = 0.08
        var gitDiffDebounce: TimeInterval = 0.4
        var showInlineBlame = true
        private var blameLabel: InlineBlameLabel?
        private var blameWork: DispatchWorkItem?
        private var blameToken = 0
        private var blameLine = -1
        private var completionRange: NSRange?
        private var ignoreNextSelectionChange = false
        private var lastRevealToken = 0
        var lastLanguage: SourceLanguage?
        var openLocation: ((URL, Int, Int) -> Void)?

        init(document: TextDocument, theme: EditorTheme) {
            self.document = document
            self.theme = theme
        }

        deinit {
            formatTask?.cancel()
            NotificationCenter.default.removeObserver(self)
        }

        /// Repaints the gutter on scroll/resize, and recomputes the git diff when
        /// a git operation happens or the window regains focus (the diff would
        /// otherwise go stale after an external commit/checkout).
        func observeScroll(of scrollView: NSScrollView) {
            let center = NotificationCenter.default
            center.addObserver(self, selector: #selector(viewportChanged), name: NSView.boundsDidChangeNotification, object: scrollView.contentView)
            center.addObserver(self, selector: #selector(viewportChanged), name: NSView.frameDidChangeNotification, object: scrollView)
            center.addObserver(self, selector: #selector(gitMaybeChanged), name: .gitDidChange, object: nil)
            center.addObserver(self, selector: #selector(gitMaybeChanged), name: NSWindow.didBecomeKeyNotification, object: nil)
        }

        @objc private func viewportChanged() {
            gutter?.refresh()
            minimap?.refresh()
            hideHover()
            hideSignatureHelp()
        }

        @objc private func gitMaybeChanged() {
            scheduleGitDiff()
            // Window reactivation can land on a gutter that was painted blank
            // while the window was inactive — repaint it too.
            gutter?.refresh()
        }

        func configurePopup() {
            popup.onAccept = { [weak self] item in
                self?.acceptCompletion(item)
            }
        }

        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            let wasLargeFile = isLargeFile
            document.applyEdit(text: textView.string, sizeHint: textView.textStorage?.length)
            isLargeFile = document.isLargeFile
            if !wasLargeFile, isLargeFile {
                disableExpensiveFeaturesForLargeFile()
            }
            lastSyncedRevision = document.revision
            // Keep the last check's markers visible until the debounced re-check
            // (LSP push or DiagnosticsService) replaces them wholesale. Clearing
            // eagerly on every keystroke made the gutter dot and the status-bar
            // count flash on each character.
            scheduleHighlight()
            scheduleGitDiff()
            scheduleLSP(in: textView)
            updateCompletionPopup(in: textView)
            scheduleSignatureHelp(in: textView)
            gutter?.refresh()
            refreshDiagnosticUnderlines()
            scheduleMinimapRebuild()
            hideHover()
            // The line content shifted; hide the now-stale blame until the
            // following selection change settles and re-queries.
            hideInlineBlame()
        }

        func textViewDidChangeSelection(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            document.updateCursor(location: textView.selectedRange().location)
            // A selection change right after typing is expected; any other one
            // (click, arrow keys, etc.) means the popup is no longer relevant.
            if ignoreNextSelectionChange {
                ignoreNextSelectionChange = false
            } else {
                popup.hide()
            }
            // Moving the caret between arguments should refresh the active
            // parameter; leaving the call dismisses the hint.
            scheduleSignatureHelp(in: textView)
            scheduleInlineBlame()
        }

        func dismissCompletions() {
            popup.hide()
            textView?.needsDisplay = true
        }

        /// ⌘D: with an empty caret, select the word under it; with a
        /// selection, add the next occurrence of that text as an additional cursor
        /// (NSTextView edits all selected ranges at once when you then type).
        func selectNextOccurrence() {
            guard let textView else { return }
            let ns = textView.string as NSString
            var ranges = textView.selectedRanges.map { $0.rangeValue }

            if ranges.count == 1, ranges[0].length == 0 {
                let word = Self.wordRange(at: ranges[0].location, in: ns)
                if word.length > 0 {
                    textView.selectedRanges = [NSValue(range: word)]
                    textView.scrollRangeToVisible(word)
                }
                return
            }

            guard let last = ranges.max(by: { $0.location < $1.location }), last.length > 0 else { return }
            let needle = ns.substring(with: last)
            let from = NSMaxRange(last)
            var found = ns.range(of: needle, options: [], range: NSRange(location: from, length: ns.length - from))
            if found.location == NSNotFound {
                found = ns.range(of: needle, options: [], range: NSRange(location: 0, length: ns.length)) // wrap
            }
            guard found.location != NSNotFound, !ranges.contains(where: { NSEqualRanges($0, found) }) else { return }
            ranges.append(found)
            textView.selectedRanges = ranges.map { NSValue(range: $0) }
            textView.scrollRangeToVisible(found)
        }

        /// Debounced LSP hover: when the mouse rests over a symbol, show its
        /// type/docs in a floating panel. Cancelled by movement, edits and scroll.
        func scheduleHover(at point: NSPoint) {
            hoverWork?.cancel()
            guard !isLargeFile, showHoverTooltips, let textView else { hoverPanel.hide(); return }
            // Hover works for diagnostics (squiggles) even without a language
            // server, so don't gate scheduling on the LSP config here.
            let work = DispatchWorkItem { [weak self] in self?.performHover(at: point, in: textView) }
            hoverWork = work
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.45, execute: work)
        }

        func hideHover() {
            hoverWork?.cancel()
            hoverPanel.hide()
            hoverIndex = -1
        }

        private func performHover(at point: NSPoint, in textView: NSTextView) {
            let ns = textView.string as NSString
            let index = textView.characterIndexForInsertion(at: point)
            guard index >= 0, index < ns.length, index != hoverIndex else { return }

            // Diagnostics win: hovering an underlined error/warning shows its
            // message right away (an inline error popover), no server needed.
            let diags = diagnostics(at: index)
            if !diags.isEmpty {
                let rect = textView.firstRect(forCharacterRange: NSRange(location: index, length: 1), actualRange: nil)
                hoverIndex = index
                hoverPanel.show(text: Self.formatDiagnostics(diags), at: rect, theme: theme)
                return
            }

            // Otherwise show LSP hover (type/docs) when a server is configured.
            guard let url = document.fileURL, LSPService.config(for: document.language) != nil else { hoverPanel.hide(); return }
            let (line, character) = Self.lspPosition(in: ns, location: index)
            let language = document.language
            let uri = url.absoluteString
            let text = textView.string
            let root = lspRootPath(for: url)
            Task { @MainActor [weak self] in
                guard let self else { return }
                let info = await LSPService.shared.hover(language: language, uri: uri, text: text, line: line, character: character, root: root)
                guard let info, !info.isEmpty else { self.hoverPanel.hide(); return }
                let rect = textView.firstRect(forCharacterRange: NSRange(location: index, length: 1), actualRange: nil)
                self.hoverIndex = index
                self.hoverPanel.show(text: info, at: rect, theme: self.theme)
            }
        }

        /// Formats one or more diagnostics for the hover popover, e.g.
        /// "Error: too few arguments  (clang)".
        private static func formatDiagnostics(_ diags: [Diagnostic]) -> String {
            diags.map { d in
                let label = switch d.severity {
                case .error: "Error"
                case .warning: "Warning"
                case .note: "Note"
                }
                let tag = d.source.map { "  (\($0))" } ?? ""
                return "\(label): \(d.message)\(tag)"
            }.joined(separator: "\n")
        }

        func hideSignatureHelp() {
            signatureWork?.cancel()
            signaturePanel.hide()
        }

        /// Debounced LSP signature help: while the caret sits inside a call's
        /// argument list, show the function signature with the active parameter
        /// bolded. Cheap local paren scan gates the request so we
        /// only hit the server when actually inside a call.
        private func scheduleSignatureHelp(in textView: NSTextView) {
            signatureWork?.cancel()
            guard !isLargeFile, document.fileURL != nil, LSPService.config(for: document.language) != nil else { signaturePanel.hide(); return }
            let selection = textView.selectedRange()
            guard selection.length == 0,
                  Self.isInsideCall(textView.string as NSString, caret: selection.location) != nil else {
                signaturePanel.hide(); return
            }
            let work = DispatchWorkItem { [weak self] in self?.requestSignatureHelp(in: textView) }
            signatureWork = work
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.12, execute: work)
        }

        private func requestSignatureHelp(in textView: NSTextView) {
            guard let url = document.fileURL else { return }
            let ns = textView.string as NSString
            let location = min(max(textView.selectedRange().location, 0), ns.length)
            let (line, character) = Self.lspPosition(in: ns, location: location)
            let language = document.language
            let uri = url.absoluteString
            let text = textView.string
            let root = lspRootPath(for: url)
            Task { @MainActor [weak self] in
                guard let self else { return }
                let signature = await LSPService.shared.signatureHelp(language: language, uri: uri, text: text, line: line, character: character, root: root)
                guard let tv = self.textView,
                      let call = Self.isInsideCall(tv.string as NSString, caret: tv.selectedRange().location) else {
                    self.signaturePanel.hide(); return
                }
                // clangd returns empty `signatures` while the surrounding code is
                // too broken to resolve the call. Recover declarations from the
                // live buffer before falling back to the last sticky result.
                let resolved: LSPSignatureHelp?
                if let signature, !signature.signatures.isEmpty {
                    resolved = signature
                } else {
                    resolved = Self.localSignatureHelp(in: tv.string, call: call)
                }
                guard let resolved, !resolved.signatures.isEmpty else { return }
                let caretRect = tv.firstRect(forCharacterRange: NSRange(location: tv.selectedRange().location, length: 0), actualRange: nil)
                self.signaturePanel.show(signature: resolved, at: caretRect, theme: self.theme)
            }
        }

        private struct CallContext {
            let identifier: String
            let openParen: Int
            let activeParameter: Int
        }

        /// Returns the innermost call containing the caret, including the callee
        /// name and active argument derived entirely from the current buffer.
        private static func isInsideCall(_ ns: NSString, caret: Int) -> CallContext? {
            let open = UInt16(UnicodeScalar("(").value)
            let close = UInt16(UnicodeScalar(")").value)
            let semicolon = UInt16(UnicodeScalar(";").value)
            let braceOpen = UInt16(UnicodeScalar("{").value)
            let braceClose = UInt16(UnicodeScalar("}").value)
            var depth = 0
            var i = min(caret, ns.length) - 1
            let limit = max(0, caret - 4000)
            while i >= limit {
                switch ns.character(at: i) {
                case close: depth += 1
                case open:
                    if depth == 0 {
                        guard let identifier = identifier(before: i, in: ns) else { return nil }
                        return CallContext(
                            identifier: identifier,
                            openParen: i,
                            activeParameter: activeParameter(in: ns, after: i, caret: caret)
                        )
                    }
                    depth -= 1
                case semicolon, braceOpen, braceClose: return nil
                default: break
                }
                i -= 1
            }
            return nil
        }

        private static func identifier(before openParen: Int, in ns: NSString) -> String? {
            var end = openParen
            while end > 0, isWhitespace(ns.character(at: end - 1)) { end -= 1 }
            var start = end
            while start > 0, isIdentifierCharacter(ns.character(at: start - 1)) { start -= 1 }
            guard start < end, !isASCIIDigit(ns.character(at: start)) else { return nil }
            return ns.substring(with: NSRange(location: start, length: end - start))
        }

        private static func activeParameter(in ns: NSString, after openParen: Int, caret: Int) -> Int {
            let end = min(max(caret, openParen + 1), ns.length)
            var parenDepth = 0
            var bracketDepth = 0
            var braceDepth = 0
            var angleDepth = 0
            var quote: unichar?
            var escaped = false
            var active = 0
            var i = openParen + 1
            while i < end {
                let character = ns.character(at: i)
                if quote != nil {
                    if escaped {
                        escaped = false
                    } else if character == 92 {
                        escaped = true
                    } else if character == quote {
                        quote = nil
                    }
                } else {
                    switch character {
                    case 34, 39: quote = character
                    case 40: parenDepth += 1
                    case 41: parenDepth = max(0, parenDepth - 1)
                    case 91: bracketDepth += 1
                    case 93: bracketDepth = max(0, bracketDepth - 1)
                    case 123: braceDepth += 1
                    case 125: braceDepth = max(0, braceDepth - 1)
                    case 60: angleDepth += 1
                    case 62: angleDepth = max(0, angleDepth - 1)
                    case 44 where parenDepth == 0 && bracketDepth == 0 && braceDepth == 0 && angleDepth == 0: active += 1
                    default: break
                    }
                }
                i += 1
            }
            return active
        }

        /// Builds signature help from prototypes and definition headers in the
        /// live buffer. This is intentionally conservative so ordinary calls are
        /// not mistaken for declarations when clangd is recovering from errors.
        private static func localSignatureHelp(in text: String, call: CallContext) -> LSPSignatureHelp? {
            let ns = text as NSString
            var searchStart = 0
            var seenLabels = Set<String>()
            var signatures: [LSPSignatureHelp.Signature] = []

            while searchStart < ns.length {
                let searchRange = NSRange(location: searchStart, length: ns.length - searchStart)
                let match = ns.range(of: call.identifier, options: [], range: searchRange)
                guard match.location != NSNotFound else { break }
                searchStart = NSMaxRange(match)

                guard isIdentifierBoundary(before: match.location, in: ns),
                      isIdentifierBoundary(after: NSMaxRange(match), in: ns) else { continue }
                var cursor = NSMaxRange(match)
                skipWhitespace(in: ns, cursor: &cursor)
                guard cursor < ns.length, ns.character(at: cursor) == 40,
                      cursor != call.openParen,
                      let closeParen = matchingParen(in: ns, openParen: cursor) else { continue }

                var terminator = closeParen + 1
                skipWhitespace(in: ns, cursor: &terminator)
                guard terminator < ns.length,
                      ns.character(at: terminator) == 59 || ns.character(at: terminator) == 123,
                      declarationPrefix(before: match.location, in: ns) != nil else { continue }

                let parameterRange = NSRange(location: cursor + 1, length: closeParen - cursor - 1)
                let labels = parameterLabels(in: ns, range: parameterRange)
                let signature = makeLocalSignature(identifier: call.identifier, parameters: labels)
                if seenLabels.insert(signature.label).inserted {
                    signatures.append(signature)
                }
            }

            guard !signatures.isEmpty else { return nil }
            let requiredCount = call.activeParameter + 1
            let activeSignature = signatures.indices.min { lhs, rhs in
                signatureScore(signatures[lhs], requiredCount: requiredCount)
                    < signatureScore(signatures[rhs], requiredCount: requiredCount)
            } ?? 0
            return LSPSignatureHelp(
                signatures: signatures,
                activeSignature: activeSignature,
                activeParameter: call.activeParameter
            )
        }

        private static func declarationPrefix(before identifier: Int, in ns: NSString) -> String? {
            var start = identifier
            while start > 0 {
                let character = ns.character(at: start - 1)
                if character == 10 || character == 13 || character == 59 || character == 123 || character == 125 { break }
                start -= 1
            }
            let raw = ns.substring(with: NSRange(location: start, length: identifier - start))
            let prefix = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !prefix.isEmpty else { return nil }

            let firstWord = prefix.split(whereSeparator: { !$0.isLetter && !$0.isNumber && $0 != "_" }).first.map(String.init)
            let expressionKeywords: Set<String> = ["return", "if", "for", "while", "switch", "case", "sizeof"]
            guard firstWord.map({ !expressionKeywords.contains($0) }) ?? false else { return nil }
            for character in prefix.utf16 {
                guard isIdentifierCharacter(character) || isWhitespace(character)
                        || character == 42 || character == 38 || character == 58
                        || character == 60 || character == 62 || character == 44
                        || character == 91 || character == 93 else { return nil }
            }
            return prefix
        }

        private static func parameterLabels(in ns: NSString, range: NSRange) -> [String] {
            guard range.length > 0 else { return [] }
            var labels: [String] = []
            var start = range.location
            var parenDepth = 0
            var bracketDepth = 0
            var braceDepth = 0
            var angleDepth = 0
            var quote: unichar?
            var escaped = false
            let end = NSMaxRange(range)
            var i = range.location

            func appendLabel(until labelEnd: Int) {
                let raw = ns.substring(with: NSRange(location: start, length: labelEnd - start))
                let label = raw.trimmingCharacters(in: .whitespacesAndNewlines)
                if !label.isEmpty { labels.append(label) }
            }

            while i < end {
                let character = ns.character(at: i)
                if quote != nil {
                    if escaped {
                        escaped = false
                    } else if character == 92 {
                        escaped = true
                    } else if character == quote {
                        quote = nil
                    }
                } else {
                    switch character {
                    case 34, 39: quote = character
                    case 40: parenDepth += 1
                    case 41: parenDepth = max(0, parenDepth - 1)
                    case 91: bracketDepth += 1
                    case 93: bracketDepth = max(0, bracketDepth - 1)
                    case 123: braceDepth += 1
                    case 125: braceDepth = max(0, braceDepth - 1)
                    case 60: angleDepth += 1
                    case 62: angleDepth = max(0, angleDepth - 1)
                    case 44 where parenDepth == 0 && bracketDepth == 0 && braceDepth == 0 && angleDepth == 0:
                        appendLabel(until: i)
                        start = i + 1
                    default: break
                    }
                }
                i += 1
            }
            appendLabel(until: end)
            return labels.count == 1 && labels[0] == "void" ? [] : labels
        }

        private static func makeLocalSignature(identifier: String, parameters: [String]) -> LSPSignatureHelp.Signature {
            let head = "\(identifier)("
            var label = head
            var offset = (head as NSString).length
            var ranges: [LSPSignatureHelp.Parameter] = []
            for (index, parameter) in parameters.enumerated() {
                if index > 0 {
                    label += ", "
                    offset += 2
                }
                let length = (parameter as NSString).length
                ranges.append(.init(start: offset, length: length))
                label += parameter
                offset += length
            }
            label += ")"
            return .init(label: label, parameters: ranges)
        }

        private static func matchingParen(in ns: NSString, openParen: Int) -> Int? {
            var depth = 0
            var quote: unichar?
            var escaped = false
            var i = openParen
            while i < ns.length {
                let character = ns.character(at: i)
                if quote != nil {
                    if escaped {
                        escaped = false
                    } else if character == 92 {
                        escaped = true
                    } else if character == quote {
                        quote = nil
                    }
                } else if character == 34 || character == 39 {
                    quote = character
                } else if character == 40 {
                    depth += 1
                } else if character == 41 {
                    depth -= 1
                    if depth == 0 { return i }
                }
                i += 1
            }
            return nil
        }

        private static func signatureScore(_ signature: LSPSignatureHelp.Signature, requiredCount: Int) -> Int {
            if signature.parameters.count >= requiredCount {
                return signature.parameters.count - requiredCount
            }
            return 1_000 + requiredCount - signature.parameters.count
        }

        private static func skipWhitespace(in ns: NSString, cursor: inout Int) {
            while cursor < ns.length, isWhitespace(ns.character(at: cursor)) { cursor += 1 }
        }

        private static func isIdentifierBoundary(before location: Int, in ns: NSString) -> Bool {
            location == 0 || !isIdentifierCharacter(ns.character(at: location - 1))
        }

        private static func isIdentifierBoundary(after location: Int, in ns: NSString) -> Bool {
            location == ns.length || !isIdentifierCharacter(ns.character(at: location))
        }

        private static func isIdentifierCharacter(_ character: unichar) -> Bool {
            character == 95 || (character >= 48 && character <= 57)
                || (character >= 65 && character <= 90) || (character >= 97 && character <= 122)
        }

        private static func isASCIIDigit(_ character: unichar) -> Bool {
            character >= 48 && character <= 57
        }

        private static func isWhitespace(_ character: unichar) -> Bool {
            character == 9 || character == 10 || character == 13 || character == 32
        }

        /// Resolves the definition of the symbol at a character index via the LSP
        /// and asks the host to open it (⌘-click / F12). Silent when unavailable.
        func goToDefinition(at index: Int) {
            guard let textView, let url = document.fileURL,
                  LSPService.config(for: document.language) != nil else { return }
            let ns = textView.string as NSString
            let safe = max(0, min(index, ns.length))
            textView.setSelectedRange(NSRange(location: safe, length: 0))
            let (line, character) = Self.lspPosition(in: ns, location: safe)
            let language = document.language
            let uri = url.absoluteString
            let text = textView.string
            let root = lspRootPath(for: url)
            Task { @MainActor [weak self] in
                guard let location = await LSPService.shared.definition(language: language, uri: uri, text: text, line: line, character: character, root: root),
                      let targetURL = URL(string: location.uri) else { return }
                self?.openLocation?(targetURL, location.line, location.column)
            }
        }

        private static func wordRange(at location: Int, in ns: NSString) -> NSRange {
            func isWord(_ u: unichar) -> Bool {
                guard let scalar = UnicodeScalar(u) else { return false }
                return CharacterSet.alphanumerics.contains(scalar) || scalar == "_"
            }
            var start = location, end = location
            while start > 0, isWord(ns.character(at: start - 1)) { start -= 1 }
            while end < ns.length, isWord(ns.character(at: end)) { end += 1 }
            return NSRange(location: start, length: end - start)
        }

        /// Builds the ordered code-completion list: structure snippets first,
        /// then clangd's semantic results, language keywords, and symbols
        /// scraped from the current buffer. No dictionary words.
        private func candidates(forPartial partial: String, in text: String) -> [CompletionItem] {
            let lowered = partial.lowercased()
            var seen = Set<String>()
            var ordered: [CompletionItem] = []
            func matches(_ label: String) -> Bool {
                !label.isEmpty && (lowered.isEmpty || label.lowercased().hasPrefix(lowered)) && label != partial
            }
            func add(_ words: [String], detail: String? = nil, kind: CompletionKind = .text) {
                for word in words where matches(word) {
                    if seen.insert(word).inserted { ordered.append(CompletionItem(label: word, detail: detail, kind: kind)) }
                }
            }

            // Snippets (for/while/do/if/switch/main/…) lead the list.
            for snippet in SnippetLibrary.snippets(for: document.language) where matches(snippet.trigger) {
                if seen.insert(snippet.trigger).inserted {
                    ordered.append(CompletionItem(label: snippet.trigger, detail: snippet.detail, snippet: snippet, kind: .snippet))
                }
            }
            // Semantic results from the language server carry signature + kind.
            for completion in lspItems where matches(completion.label) {
                if seen.insert(completion.label).inserted {
                    ordered.append(CompletionItem(label: completion.label, detail: completion.detail, kind: CompletionKind(lspKind: completion.kind)))
                }
            }
            add(document.language.completionWords, kind: .keyword)
            add(globalCompletionWords, kind: .keyword)
            add(bufferSymbols(in: text, excluding: partial), kind: .variable)
            return Array(ordered.prefix(120))
        }

        func textView(_ textView: NSTextView, shouldChangeTextIn range: NSRange, replacementString: String?) -> Bool {
            // With multiple cursors, let AppKit apply the edit to every range
            // verbatim — auto-pairing one range would desync the others.
            if textView.selectedRanges.count > 1 { return true }
            guard let string = replacementString, range.length == 0, string.count == 1 else { return true }
            let pairs: [Character: Character] = ["{": "}", "(": ")", "[": "]", "\"": "\"", "'": "'"]
            guard let opener = string.first, let closer = pairs[opener] else { return true }
            textView.insertText("\(opener)\(closer)", replacementRange: range)
            textView.setSelectedRange(NSRange(location: range.location + 1, length: 0))
            return false
        }

        func textView(_ textView: NSTextView, doCommandBy selector: Selector) -> Bool {
            // While the suggestion popup is open it captures navigation keys.
            if popup.isVisible {
                switch selector {
                case #selector(NSResponder.moveUp(_:)):
                    popup.moveSelection(by: -1); return true
                case #selector(NSResponder.moveDown(_:)):
                    popup.moveSelection(by: 1); return true
                case #selector(NSResponder.scrollPageUp(_:)), #selector(NSResponder.pageUp(_:)):
                    popup.moveSelection(by: -popup.pageStep); return true
                case #selector(NSResponder.scrollPageDown(_:)), #selector(NSResponder.pageDown(_:)):
                    popup.moveSelection(by: popup.pageStep); return true
                case #selector(NSResponder.insertNewline(_:)), #selector(NSResponder.insertTab(_:)):
                    popup.acceptSelection(); return true
                case #selector(NSResponder.cancelOperation(_:)), #selector(NSResponder.complete(_:)):
                    popup.hide(); return true
                default:
                    break
                }
            }

            switch selector {
            case #selector(NSResponder.insertTab(_:)):
                textView.insertText(indentUnit, replacementRange: textView.selectedRange())
                return true
            case #selector(NSResponder.insertNewline(_:)):
                insertSmartNewline(in: textView)
                return true
            case #selector(NSResponder.deleteBackward(_:)):
                return smartOutdent(in: textView)
            case #selector(NSResponder.complete(_:)):
                updateCompletionPopup(in: textView, minimumPrefix: 0)
                return true
            case #selector(NSResponder.cancelOperation(_:)):
                if signaturePanel.isVisible {
                    hideSignatureHelp()
                    return true
                }
                // Collapse multiple cursors back to a single caret.
                if textView.selectedRanges.count > 1 {
                    let primary = textView.selectedRanges.last?.rangeValue ?? textView.selectedRange()
                    textView.setSelectedRange(NSRange(location: NSMaxRange(primary), length: 0))
                    return true
                }
                return false
            default:
                return false
            }
        }

        func applyHighlight() {
            guard let textView else { return }
            guard !isLargeFile else {
                treeSitterHighlighter = nil
                treeSitterAttemptedLanguage = nil
                TextKit2SyntaxHighlighter.clear(in: textView, theme: theme)
                return
            }
            if useTreeSitterIfAvailable(in: textView) {
                return
            }
            TextKit2SyntaxHighlighter.apply(to: textView, language: document.language, theme: theme)
        }

        func forceHighlightRefresh() {
            applyHighlight()
            treeSitterHighlighter?.invalidate()
        }

        private func useTreeSitterIfAvailable(in textView: NSTextView) -> Bool {
            let language = document.language
            guard TreeSitterHighlighter.supports(language) else {
                treeSitterHighlighter = nil
                treeSitterAttemptedLanguage = language
                return false
            }

            if treeSitterAttemptedLanguage != language {
                treeSitterHighlighter = nil
                treeSitterAttemptedLanguage = language

                // Paint immediately with the cheap regex pass so the file is
                // never shown uncolored, then let tree-sitter refine the visible
                // region on top. The expensive part was the ~1.5s query compile
                // (now cached/warmed), not this pass.
                TextKit2SyntaxHighlighter.apply(to: textView, language: language, theme: theme)

                if let config = TreeSitterHighlighter.cachedConfiguration(for: language) {
                    treeSitterHighlighter = try? TreeSitterHighlighter(
                        textView: textView,
                        language: language,
                        configuration: config,
                        theme: theme
                    )
                }
                if treeSitterHighlighter == nil {
                    // Grammar still compiling (off-main): keep the regex colors
                    // and swap in tree-sitter once `prepareConfiguration` lands.
                    activateTreeSitterWhenReady(for: language)
                }
            }

            guard let treeSitterHighlighter else { return false }
            treeSitterHighlighter.updateTheme(theme)
            return true
        }

        /// Compiles the grammar off the main thread, then installs the parser and
        /// drops the regex highlighting — but only if the editor still shows the
        /// same language and hasn't grown into large-file mode meanwhile.
        private func activateTreeSitterWhenReady(for language: SourceLanguage) {
            Task { @MainActor [weak self] in
                guard let config = await TreeSitterHighlighter.prepareConfiguration(for: language) else { return }
                guard let self,
                      let textView = self.textView,
                      self.document.language == language,
                      self.treeSitterAttemptedLanguage == language,
                      self.treeSitterHighlighter == nil,
                      !self.isLargeFile else { return }
                self.treeSitterHighlighter = try? TreeSitterHighlighter(
                    textView: textView,
                    language: language,
                    configuration: config,
                    theme: self.theme
                )
                self.treeSitterHighlighter?.updateTheme(self.theme)
            }
        }

        func disableExpensiveFeaturesForLargeFile() {
            highlightWork?.cancel()
            gitWork?.cancel()
            lspWork?.cancel()
            minimapWork?.cancel()
            hoverWork?.cancel()
            signatureWork?.cancel()
            popup.hide()
            hoverPanel.hide()
            signaturePanel.hide()
            lspItems = []
            treeSitterHighlighter = nil
            treeSitterAttemptedLanguage = nil
            if let uri = lspDiagnosticsURI {
                LSPDiagnosticsBus.shared.removeHandler(uri: uri)
                if let language = lspLanguage {
                    Task { await LSPService.shared.didClose(language: language, uri: uri) }
                }
            }
            lspDiagnosticsURI = nil
            lspLanguage = nil
            lspRoot = nil
            folding.unfoldAll()
            folding.updateRegions([])
            gutter?.setGitDiff(nil)
            document.diagnostics = []
            hideInlineBlame()
            if let textView {
                TextKit2SyntaxHighlighter.clear(in: textView, theme: theme)
                (textView as? BriskCodeTextView)?.setDiagnosticUnderlines([])
            }
        }

        // MARK: - Inline git blame

        /// Adds the faint trailing label that shows who last touched the caret's
        /// line. Lives as a subview of the text view (document coordinates) so it
        /// scrolls with the text.
        func installBlameLabel(in textView: NSTextView) {
            guard blameLabel == nil else { return }
            let label = InlineBlameLabel()
            label.isHidden = true
            textView.addSubview(label)
            blameLabel = label
        }

        func updateInlineBlameEnabled(_ enabled: Bool) {
            guard showInlineBlame != enabled else { return }
            showInlineBlame = enabled
            if enabled {
                scheduleInlineBlame()
            } else {
                hideInlineBlame()
            }
        }

        func hideInlineBlame() {
            blameWork?.cancel()
            blameLine = -1
            blameLabel?.isHidden = true
        }

        /// Debounced: looks up `git blame` for the caret's line and shows the
        /// result as ghost text after the line. Skipped for large files, plain
        /// buffers, multi-character selections, and outside a repo.
        func scheduleInlineBlame() {
            blameWork?.cancel()
            guard showInlineBlame, !isLargeFile,
                  let textView, let fileURL = document.fileURL,
                  let root = workspaceRootURL else { hideInlineBlame(); return }
            let selection = textView.selectedRange()
            guard selection.length == 0 else { hideInlineBlame(); return }
            // `document.cursorLine` is already maintained (binary search in
            // `updateCursor`, called just before this), so avoid an O(n)
            // substring+split of the whole prefix on every caret move.
            let line = document.cursorLine
            // Same line as the last shown blame: keep it (just reposition cheaply).
            if line == blameLine, blameLabel?.isHidden == false {
                positionInlineBlame()
                return
            }
            blameToken &+= 1
            let token = blameToken
            let work = DispatchWorkItem { [weak self] in
                guard let self else { return }
                Task { @MainActor in
                    guard token == self.blameToken else { return }
                    let blame = await GitService.blame(file: fileURL, line: line, root: root)
                    guard token == self.blameToken, let blame, let label = self.blameLabel else {
                        self.blameLabel?.isHidden = true
                        return
                    }
                    self.blameLine = line
                    label.configure(text: blame.detailedLabel, color: self.theme.comment, font: self.theme.nsFont)
                    self.positionInlineBlame()
                }
            }
            blameWork = work
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.35, execute: work)
        }

        /// Places the blame label just past the end of the caret's line, vertically
        /// centered on it, in the text view's (document) coordinate space.
        private func positionInlineBlame() {
            guard let textView, let label = blameLabel, !label.stringValue.isEmpty else { return }
            let ns = textView.string as NSString
            let caret = min(textView.selectedRange().location, ns.length)
            let lineRange = ns.lineRange(for: NSRange(location: caret, length: 0))
            var eol = NSMaxRange(lineRange)
            while eol > lineRange.location {
                let c = ns.character(at: eol - 1)
                if c == 0x0A || c == 0x0D { eol -= 1 } else { break }
            }
            let screenRect = textView.firstRect(forCharacterRange: NSRange(location: eol, length: 0), actualRange: nil)
            guard let window = textView.window, screenRect.height > 0 else { label.isHidden = true; return }
            let winRect = window.convertFromScreen(screenRect)
            let viewRect = textView.convert(winRect, from: nil)
            label.sizeToFit()
            let gap: CGFloat = 18
            label.frame.origin = NSPoint(x: viewRect.minX + gap, y: viewRect.minY)
            label.frame.size.height = viewRect.height
            label.isHidden = false
        }

        /// Reformats the whole buffer with the language's external formatter.
        /// Applies the result through the text view's editing path
        /// (`shouldChangeText`/`didChangeText`) rather than re-seeding the
        /// document, so AppKit records it as a single undoable step (⌘Z reverts
        /// the format) and `textDidChange` updates the document like normal
        /// typing. Silent no-op when the tool is missing or formatting fails,
        /// matching format-on-save.
        func formatDocument() {
            guard formatTask == nil else { return }
            let doc = document
            let text = doc.text
            let language = doc.language
            let url = doc.fileURL
            guard language.supportsFormatting else { return }
            let indentWidth = theme.tabWidth
            formatTask = Task { @MainActor [weak self] in
                let formatted = await FormatterService.format(
                    text: text,
                    language: language,
                    fileURL: url,
                    indentWidth: indentWidth
                )
                guard let self else { return }
                defer { self.formatTask = nil }
                guard !Task.isCancelled,
                      let formatted,
                      let textView = self.textView,
                      textView.string == text,
                      formatted != text else { return }
                let fullRange = NSRange(location: 0, length: (textView.string as NSString).length)
                guard textView.shouldChangeText(in: fullRange, replacementString: formatted) else { return }
                let selection = textView.selectedRange()
                textView.textStorage?.replaceCharacters(in: fullRange, with: formatted)
                textView.didChangeText()
                let newLength = (textView.string as NSString).length
                textView.setSelectedRange(NSRange(location: min(selection.location, newLength), length: 0))
            }
        }

        /// Scrolls to and selects a navigation target (Find in Files, outline,
        /// definition) when the document's `revealToken` advances. Cheap no-op on
        /// the many `updateNSView` passes where nothing new was requested.
        func applyPendingReveal() {
            guard let textView, document.revealToken != lastRevealToken else { return }
            lastRevealToken = document.revealToken
            guard let reveal = document.pendingReveal else { return }
            let range = document.range(line: reveal.line, column: reveal.column, length: reveal.length)
            textView.setSelectedRange(range)
            textView.scrollRangeToVisible(range)
            textView.window?.makeFirstResponder(textView)
        }

        private func scheduleHighlight() {
            highlightWork?.cancel()
            guard !isLargeFile else { return }
            let work = DispatchWorkItem { [weak self] in
                self?.recomputeFoldRegions()
                if self?.treeSitterHighlighter == nil {
                    self?.applyHighlight()
                }
            }
            highlightWork = work
            DispatchQueue.main.asyncAfter(deadline: .now() + highlightDebounce, execute: work)
        }

        /// Re-detects foldable regions after an edit. The analysis is cheap
        /// (indentation only); the content-storage relayout inside `updateRegions`
        /// only fires when something is actually folded, so plain typing stays
        /// untouched by the folding machinery.
        func recomputeFoldRegions() {
            guard let textView else { return }
            guard !isLargeFile, theme.showCodeFolding, document.language.supportsFolding else {
                folding.unfoldAll()
                folding.updateRegions([])
                gutter?.refresh()
                return
            }
            let regions = FoldingAnalyzer.regions(in: textView.string as NSString, tabWidth: theme.tabWidth)
            folding.updateRegions(regions)
            gutter?.refresh()
        }

        /// Debounced minimap content rebuild. The minimap re-scans the whole
        /// document to build its per-line word bars; doing that on every keystroke
        /// (each draw) is wasteful, so coalesce rapid typing into a single rebuild
        /// once edits settle — the overview can lag a beat without anyone noticing.
        private func scheduleMinimapRebuild() {
            guard !isLargeFile, minimap?.isHidden == false else { return }
            minimapWork?.cancel()
            let work = DispatchWorkItem { [weak self] in self?.minimap?.invalidateContent() }
            minimapWork = work
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2, execute: work)
        }

        /// Debounced recompute of the git gutter diff (buffer vs HEAD). Cleared
        /// for documents with no on-disk URL.
        func scheduleGitDiff() {
            gitWork?.cancel()
            guard gutter != nil else { return }
            guard !isLargeFile else { gutter?.setGitDiff(nil); return }
            guard document.fileURL != nil else { gutter?.setGitDiff(nil); return }
            let work = DispatchWorkItem { [weak self] in
                guard let self, let tv = self.textView, let url = self.document.fileURL else { return }
                let text = tv.string
                Task { @MainActor [weak self] in
                    let diff = await GitService.diff(for: url, currentText: text)
                    self?.gutter?.setGitDiff(diff)
                }
            }
            gitWork = work
            DispatchQueue.main.asyncAfter(deadline: .now() + gitDiffDebounce, execute: work)
        }

        /// Recomputes the suggestion list for the identifier at the caret and
        /// shows/updates the floating popup. Never mutates the document.
        private func updateCompletionPopup(in textView: NSTextView, minimumPrefix: Int = 2) {
            guard !isLargeFile, document.language != .plainText else { popup.hide(); return }
            let selection = textView.selectedRange()
            guard selection.length == 0 else { popup.hide(); return }

            let nsString = textView.string as NSString
            var start = selection.location
            while start > 0, let s = UnicodeScalar(nsString.character(at: start - 1)),
                  CharacterSet.alphanumerics.contains(s) || s == "_" {
                start -= 1
            }
            let partial = nsString.substring(with: NSRange(location: start, length: selection.location - start))
            guard partial.count >= minimumPrefix else { popup.hide(); return }

            let items = candidates(forPartial: partial, in: textView.string)
            // A single plain suggestion equal to what's typed isn't helpful;
            // a snippet match always is.
            let onlyEcho = items.count == 1 && items[0].label == partial && items[0].snippet == nil
            guard !items.isEmpty, !onlyEcho else { popup.hide(); return }

            completionRange = NSRange(location: start, length: selection.location - start)
            let caretRect = textView.firstRect(forCharacterRange: NSRange(location: start, length: 0), actualRange: nil)
            ignoreNextSelectionChange = true
            popup.show(items: items, caretScreenRect: caretRect, parent: textView.window)
            textView.needsDisplay = true
        }

        private func acceptCompletion(_ item: CompletionItem) {
            guard let textView, let range = completionRange else { return }
            let nsString = textView.string as NSString

            let insertText: String
            var selection: NSRange?
            if let snippet = item.snippet {
                // Indent continuation lines to match the snippet's start column.
                let lineStart = nsString.lineRange(for: NSRange(location: range.location, length: 0)).location
                var baseIndent = ""
                var offset = lineStart
                while offset < range.location, let s = UnicodeScalar(nsString.character(at: offset)), s == " " || s == "\t" {
                    baseIndent.append(Character(s))
                    offset += 1
                }
                let expansion = SnippetExpander.expand(snippet, baseIndent: baseIndent, indentUnit: indentUnit)
                insertText = expansion.text
                selection = expansion.selection
            } else {
                insertText = item.label
            }

            // Absorb a leading `#` that's already in the buffer (e.g. user typed
            // `#def` and accepts the `#define` snippet) so we don't get `##define`.
            var insertLocation = range.location
            var length = min(range.length, nsString.length - range.location)
            if insertText.first == "#", insertLocation > 0, nsString.character(at: insertLocation - 1) == 35 {
                insertLocation -= 1
                length += 1
            }

            textView.insertText(insertText, replacementRange: NSRange(location: insertLocation, length: length))
            if let selection {
                textView.setSelectedRange(NSRange(location: insertLocation + selection.location, length: selection.length))
            }
            completionRange = nil
        }

        /// Debounced semantic completion prefetch + buffer sync via the language
        /// server for any supported language backed by a real path. Cancelling
        /// the prior work item coalesces edit bursts so only the final buffer is
        /// sent through `didChange`. Failures keep the local completion fallback.
        private func scheduleLSP(in textView: NSTextView) {
            let language = document.language
            guard !isLargeFile, LSPService.config(for: language) != nil, let url = document.fileURL else {
                lspItems = []
                return
            }
            lspWork?.cancel()

            let text = textView.string
            let nsString = text as NSString
            let (line, character) = Self.lspPosition(in: nsString, location: textView.selectedRange().location)
            let uri = url.absoluteString
            let root = lspRootPath(for: url)

            let work = DispatchWorkItem { [weak self] in
                Task { @MainActor [weak self] in
                    let items = await LSPService.shared.completions(
                        language: language, uri: uri, text: text,
                        line: line, character: character, root: root
                    )
                    guard let self, !items.isEmpty else { return }
                    self.lspItems = items
                    // Fold fresh semantic results into an already-open popup.
                    if self.popup.isVisible, let tv = self.textView {
                        self.updateCompletionPopup(in: tv)
                    }
                }
            }
            lspWork = work
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15, execute: work)
        }

        /// Starts the language server as soon as a supported file opens, registers
        /// for its diagnostics, and primes the first completion so the launch cost
        /// isn't paid mid-type.
        func warmUpLSP() {
            guard !isLargeFile, let textView, let url = document.fileURL else { return }
            let language = document.language
            guard LSPService.config(for: language) != nil else { return }
            let uri = url.absoluteString
            let root = lspRootPath(for: url)
            lspDiagnosticsURI = uri
            lspLanguage = language
            lspRoot = root
            // Route this server's diagnostics into the document for the gutter.
            LSPDiagnosticsBus.shared.setHandler(uri: uri) { [weak self] diagnostics in
                self?.document.diagnostics = diagnostics
            }
            let text = textView.string
            Task { @MainActor in
                await LSPService.shared.openDocument(language: language, uri: uri, text: text, root: root)
            }
            scheduleLSP(in: textView)
        }

        func syncLSPIdentity() {
            guard !isLargeFile else { return }
            let uri = document.fileURL?.absoluteString
            let language = document.language
            let root = document.fileURL.map(lspRootPath)
            guard uri != lspDiagnosticsURI || language != lspLanguage || root != lspRoot else { return }
            if let oldURI = lspDiagnosticsURI {
                LSPDiagnosticsBus.shared.removeHandler(uri: oldURI)
                if let oldLanguage = lspLanguage {
                    Task { await LSPService.shared.didClose(language: oldLanguage, uri: oldURI) }
                }
            }
            lspDiagnosticsURI = nil
            lspLanguage = nil
            lspRoot = nil
            lspItems = []
            document.diagnostics = []
            warmUpLSP()
        }

        private func lspRootPath(for url: URL) -> String {
            workspaceRootURL?.path ?? url.deletingLastPathComponent().path
        }

        private static func lspPosition(in nsString: NSString, location: Int) -> (line: Int, character: Int) {
            let safe = max(0, min(location, nsString.length))
            let lineRange = nsString.lineRange(for: NSRange(location: safe, length: 0))
            let character = safe - lineRange.location
            var line = 0
            if lineRange.location > 0 {
                nsString.enumerateSubstrings(in: NSRange(location: 0, length: lineRange.location), options: [.byLines, .substringNotRequired]) { _, _, _, _ in
                    line += 1
                }
            }
            return (line, character)
        }

        /// Maps the document's diagnostics to resolved character ranges and hands
        /// them to the text view to draw as squiggles. Recomputed from the live
        /// buffer so the underlines track the text between LSP publishes.
        func refreshDiagnosticUnderlines() {
            guard let textView = textView as? BriskCodeTextView else { return }
            guard !isLargeFile else {
                textView.setDiagnosticUnderlines([])
                return
            }
            let ns = textView.string as NSString
            let underlines: [(range: NSRange, severity: Diagnostic.Severity)] = document.diagnostics.compactMap { d in
                guard d.severity != .note, let range = Self.diagnosticRange(for: d, in: ns) else { return nil }
                return (range, d.severity)
            }
            textView.setDiagnosticUnderlines(underlines)
        }

        /// Resolves a diagnostic's span to a character range: the real end when
        /// the source gave one (LSP), otherwise the token at the start column
        /// (the clang/swiftc fallback only reports a point).
        static func diagnosticRange(for d: Diagnostic, in ns: NSString) -> NSRange? {
            guard let lineStart = lineStartOffset(in: ns, line1: d.line) else { return nil }
            let start = min(ns.length, lineStart + max(0, d.column - 1))
            if let endLine = d.endLine, let endColumn = d.endColumn,
               let endLineStart = lineStartOffset(in: ns, line1: endLine) {
                let end = min(ns.length, endLineStart + max(0, endColumn - 1))
                if end > start { return NSRange(location: start, length: end - start) }
            }
            let word = wordRange(at: start, in: ns)
            if word.length > 0 { return word }
            let len = min(1, ns.length - start)
            return len > 0 ? NSRange(location: start, length: len) : nil
        }

        /// Character offset of the 1-based line's first character, or nil if the
        /// line is past the end of the buffer.
        private static func lineStartOffset(in ns: NSString, line1: Int) -> Int? {
            if line1 <= 1 { return 0 }
            var lineNo = 1
            var result: Int?
            ns.enumerateSubstrings(in: NSRange(location: 0, length: ns.length), options: [.byLines, .substringNotRequired]) { _, _, enclosingRange, stop in
                lineNo += 1
                if lineNo == line1 {
                    result = NSMaxRange(enclosingRange)
                    stop.pointee = true
                }
            }
            return result
        }

        /// The diagnostic(s) whose span covers a character index, for the hover.
        func diagnostics(at index: Int) -> [Diagnostic] {
            guard let textView else { return [] }
            let ns = textView.string as NSString
            return document.diagnostics.filter { d in
                guard let range = Self.diagnosticRange(for: d, in: ns) else { return false }
                return NSLocationInRange(index, range) || index == NSMaxRange(range)
            }
        }

        /// Unique identifiers found in the buffer — gives "suggest my own
        /// variable / function names" without needing a language server.
        private func bufferSymbols(in text: String, excluding partial: String) -> [String] {
            guard text.utf16.count <= 200_000 else { return [] }
            guard let regex = Self.identifierRegex else { return [] }
            let nsText = text as NSString
            var counts: [String: Int] = [:]
            regex.enumerateMatches(in: text, range: NSRange(location: 0, length: nsText.length)) { match, _, _ in
                guard let match else { return }
                let token = nsText.substring(with: match.range)
                guard token != partial, token.count >= 3, !Self.reservedTokens.contains(token) else { return }
                counts[token, default: 0] += 1
            }
            return counts.keys.sorted { lhs, rhs in
                if counts[lhs] != counts[rhs] { return counts[lhs]! > counts[rhs]! }
                return lhs.localizedStandardCompare(rhs) == .orderedAscending
            }
        }

        private static let identifierRegex = try? NSRegularExpression(pattern: "[A-Za-z_][A-Za-z0-9_]{2,}")
        private static let reservedTokens: Set<String> = ["int", "for", "the", "and", "var", "let", "void", "return"]

        private var indentUnit: String {
            theme.usesSpacesForTabs ? String(repeating: " ", count: theme.tabWidth) : "\t"
        }

        private let globalCompletionWords = [
            "TODO:", "MARK:", "FIXME:", "main", "printf", "scanf", "return", "true", "false", "NULL", "nil"
        ]

        /// Backspace inside a line's leading whitespace removes a whole indent
        /// level (back to the previous tab stop) in one keystroke instead of one
        /// space at a time. Engages only in spaces mode, with a single empty
        /// caret sitting in pure leading whitespace; every other case returns
        /// false so AppKit's default delete (selection delete, line-join,
        /// tab-mode) runs unchanged.
        private func smartOutdent(in textView: NSTextView) -> Bool {
            guard theme.usesSpacesForTabs,
                  textView.selectedRanges.count == 1 else { return false }
            let selection = textView.selectedRange()
            guard selection.length == 0, selection.location > 0 else { return false }
            let nsString = textView.string as NSString
            let lineStart = nsString.lineRange(for: NSRange(location: selection.location, length: 0)).location
            let width = selection.location - lineStart
            guard width > 0 else { return false }            // caret at line start -> default join
            for offset in lineStart..<selection.location {   // only when caret is in leading whitespace
                let c = nsString.character(at: offset)
                guard c == 0x20 || c == 0x09 else { return false }
            }
            let tab = max(theme.tabWidth, 1)
            let removal = width - ((width - 1) / tab) * tab  // distance to previous tab stop (e.g. 15->3, 12->4)
            textView.insertText("", replacementRange: NSRange(location: selection.location - removal, length: removal))
            return true
        }

        private func insertSmartNewline(in textView: NSTextView) {
            let nsString = textView.string as NSString
            let selection = textView.selectedRange()
            let lineRange = nsString.lineRange(for: NSRange(location: selection.location, length: 0))
            let lineStart = lineRange.location
            var offset = lineStart
            var indent = ""
            while offset < selection.location {
                guard let scalar = UnicodeScalar(nsString.character(at: offset)), scalar == " " || scalar == "\t" else { break }
                indent.append(Character(scalar))
                offset += 1
            }

            let previous: Character? = selection.location > 0 ? UnicodeScalar(nsString.character(at: selection.location - 1)).map(Character.init) : nil
            let next: Character? = selection.location < nsString.length ? UnicodeScalar(nsString.character(at: selection.location)).map(Character.init) : nil
            let bracketPairs: [Character: Character] = ["{": "}", "(": ")", "[": "]"]

            // Caret sits between an opening and its matching closing bracket
            // (e.g. just typed `{` -> `{|}`): open up an indented body and push
            // the closing bracket onto its own line at the outer indent.
            if let prev = previous, let closer = bracketPairs[prev], next == closer {
                let body = "\n" + indent + indentUnit
                let tail = "\n" + indent
                textView.insertText(body + tail, replacementRange: selection)
                let caret = selection.location + (body as NSString).length
                textView.setSelectedRange(NSRange(location: caret, length: 0))
                return
            }

            // If the line being left holds only whitespace (auto-indent the user
            // never typed into), drop that phantom indent as part of this edit so
            // the abandoned line stays empty instead of accumulating trailing
            // spaces. The new line still gets `indent`, so the caret column is
            // unchanged.
            var replacement = selection
            if offset == selection.location, selection.length == 0,
               isTrailingWhitespaceOnly(nsString, from: selection.location, lineEnd: NSMaxRange(lineRange)) {
                replacement = NSRange(location: lineStart, length: selection.location - lineStart)
            }

            var insertion = "\n" + indent
            if let prev = previous, bracketPairs[prev] != nil || prev == ":" {
                insertion += indentUnit
            }
            textView.insertText(insertion, replacementRange: replacement)
        }

        /// True when everything from `location` to the line's end (excluding the
        /// terminating newline) is whitespace — i.e. there is no real code after
        /// the caret on this line.
        private func isTrailingWhitespaceOnly(_ nsString: NSString, from location: Int, lineEnd: Int) -> Bool {
            var i = location
            while i < lineEnd {
                let c = nsString.character(at: i)
                if c == 0x0A || c == 0x0D { break }
                if c != 0x20 && c != 0x09 { return false }
                i += 1
            }
            return true
        }
    }
}

/// The faint trailing "author · when · summary" label rendered after the caret's
/// line. Non-interactive: clicks pass straight through to the text view so it
/// never blocks selection or the caret.
final class InlineBlameLabel: NSTextField {
    init() {
        super.init(frame: .zero)
        isEditable = false
        isSelectable = false
        isBordered = false
        isBezeled = false
        drawsBackground = false
        refusesFirstResponder = true
        lineBreakMode = .byTruncatingTail
        cell?.usesSingleLineMode = true
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func configure(text: String, color: NSColor, font baseFont: NSFont) {
        stringValue = text
        // A touch smaller than the editor font and dimmed, so it reads as a hint.
        let size = max(9, baseFont.pointSize - 1.5)
        font = NSFont(descriptor: baseFont.fontDescriptor.withSymbolicTraits(.italic), size: size)
            ?? NSFont.systemFont(ofSize: size)
        textColor = color.withAlphaComponent(0.55)
    }

    override func hitTest(_ point: NSPoint) -> NSView? { nil }
}
