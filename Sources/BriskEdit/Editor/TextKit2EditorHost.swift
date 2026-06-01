import AppKit
import SwiftUI

/// NSTextView subclass that notifies the coordinator when it loses focus, so
/// the floating completion popup can be dismissed.
final class BriskCodeTextView: NSTextView {
    var onResignFirstResponder: (() -> Void)?
    var onBecomeFirstResponder: (() -> Void)?

    override func resignFirstResponder() -> Bool {
        onResignFirstResponder?()
        return super.resignFirstResponder()
    }

    override func becomeFirstResponder() -> Bool {
        let became = super.becomeFirstResponder()
        if became { onBecomeFirstResponder?() }
        return became
    }
}

struct TextKit2EditorHost: NSViewRepresentable {
    @Bindable var document: TextDocument
    let theme: EditorTheme

    func makeNSView(context: Context) -> NSView {
        let textView = BriskCodeTextView(usingTextLayoutManager: true)
        textView.delegate = context.coordinator
        textView.string = document.text
        configure(textView, theme: theme)
        context.coordinator.textView = textView
        context.coordinator.document = document
        context.coordinator.theme = theme
        textView.onResignFirstResponder = { [weak coordinator = context.coordinator] in
            coordinator?.dismissCompletions()
        }
        // Returning to the editor (e.g. after committing in the terminal) should
        // refresh the gutter's git diff, which is otherwise stale.
        textView.onBecomeFirstResponder = { [weak coordinator = context.coordinator] in
            coordinator?.scheduleGitDiff()
        }
        context.coordinator.configurePopup()

        let scrollView = NSScrollView()
        scrollView.borderType = .noBorder
        scrollView.drawsBackground = true
        scrollView.backgroundColor = theme.background
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

        let container = NSView()
        // Let SwiftUI own the container's frame (TAMIC = true, the AppKit
        // default — same as the PDF/QuickLook preview hosts). Keeping this
        // `false` left the container's *own* size undefined: its subviews are
        // pinned to its edges, but nothing constrains its height, so SwiftUI
        // measured it ambiguously and the editor overflowed upward — collapsing
        // the open-files tab strip to zero height. Only the subviews use
        // Auto Layout; they lay out inside whatever frame SwiftUI assigns.
        gutter.translatesAutoresizingMaskIntoConstraints = false
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(gutter)
        container.addSubview(scrollView)
        NSLayoutConstraint.activate([
            gutter.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            gutter.topAnchor.constraint(equalTo: container.topAnchor),
            gutter.bottomAnchor.constraint(equalTo: container.bottomAnchor),
            gutter.widthAnchor.constraint(equalToConstant: TextKit2GutterView.width),
            scrollView.leadingAnchor.constraint(equalTo: gutter.trailingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            scrollView.topAnchor.constraint(equalTo: container.topAnchor),
            scrollView.bottomAnchor.constraint(equalTo: container.bottomAnchor)
        ])

        // Repaint the gutter as the text scrolls or the viewport resizes.
        scrollView.contentView.postsBoundsChangedNotifications = true
        context.coordinator.observeScroll(of: scrollView)

        context.coordinator.lastSyncedRevision = document.revision
        context.coordinator.applyHighlight()
        context.coordinator.warmUpLSP()
        context.coordinator.scheduleGitDiff()
        DispatchQueue.main.async { [weak scrollView, weak textView] in
            scrollView?.window?.makeFirstResponder(textView)
        }
        return container
    }

    func updateNSView(_ container: NSView, context: Context) {
        guard let textView = context.coordinator.textView else { return }
        let coordinator = context.coordinator
        coordinator.document = document
        let themeChanged = coordinator.theme != theme
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
            coordinator.gutter?.setTheme(theme)
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
        // here for an external re-seed or a theme switch.
        if didReseed || themeChanged {
            coordinator.applyHighlight()
        }
        coordinator.gutter?.setDiagnostics(document.diagnostics)
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
        weak var scrollView: NSScrollView?
        private var highlightWork: DispatchWorkItem?
        private var gitWork: DispatchWorkItem?
        private var lspWork: DispatchWorkItem?
        private var lspItems: [LSPCompletion] = []
        private var lspDiagnosticsURI: String?
        var lastSyncedRevision = 0
        private let popup = CompletionPopup()
        private var completionRange: NSRange?
        private var ignoreNextSelectionChange = false

        init(document: TextDocument, theme: EditorTheme) {
            self.document = document
            self.theme = theme
        }

        deinit {
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
            document.applyEdit(text: textView.string)
            lastSyncedRevision = document.revision
            // Keep the last check's markers visible until the debounced re-check
            // (LSP push or DiagnosticsService) replaces them wholesale. Clearing
            // eagerly on every keystroke made the gutter dot and the status-bar
            // count flash on each character.
            scheduleHighlight()
            scheduleGitDiff()
            scheduleLSP(in: textView)
            updateCompletionPopup(in: textView)
            gutter?.refresh()
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
        }

        func dismissCompletions() {
            popup.hide()
            textView?.needsDisplay = true
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
            case #selector(NSResponder.complete(_:)):
                updateCompletionPopup(in: textView, minimumPrefix: 0)
                return true
            default:
                return false
            }
        }

        func applyHighlight() {
            guard let textView else { return }
            TextKit2SyntaxHighlighter.apply(to: textView, language: document.language, theme: theme)
        }

        private func scheduleHighlight() {
            highlightWork?.cancel()
            let work = DispatchWorkItem { [weak self] in
                self?.applyHighlight()
            }
            highlightWork = work
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.08, execute: work)
        }

        /// Debounced recompute of the git gutter diff (buffer vs HEAD). Cleared
        /// for documents with no on-disk URL.
        func scheduleGitDiff() {
            gitWork?.cancel()
            guard gutter != nil else { return }
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
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4, execute: work)
        }

        /// Recomputes the suggestion list for the identifier at the caret and
        /// shows/updates the floating popup. Never mutates the document.
        private func updateCompletionPopup(in textView: NSTextView, minimumPrefix: Int = 2) {
            guard document.language != .plainText else { popup.hide(); return }
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
        /// server for any supported language backed by a real path. Completions
        /// land in `lspItems`; diagnostics arrive asynchronously over the bus.
        /// Failures are silent — the editor keeps its keyword/buffer fallback.
        private func scheduleLSP(in textView: NSTextView) {
            let language = document.language
            guard LSPService.config(for: language) != nil, let url = document.fileURL else {
                lspItems = []
                return
            }
            lspWork?.cancel()

            let text = textView.string
            let nsString = text as NSString
            let (line, character) = Self.lspPosition(in: nsString, location: textView.selectedRange().location)
            let uri = url.absoluteString
            let root = url.deletingLastPathComponent().path

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
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05, execute: work)
        }

        /// Starts the language server as soon as a supported file opens, registers
        /// for its diagnostics, and primes the first completion so the launch cost
        /// isn't paid mid-type.
        func warmUpLSP() {
            guard let textView, let url = document.fileURL else { return }
            let language = document.language
            guard LSPService.config(for: language) != nil else { return }
            let uri = url.absoluteString
            lspDiagnosticsURI = uri
            // Route this server's diagnostics into the document for the gutter.
            LSPDiagnosticsBus.shared.setHandler(uri: uri) { [weak self] diagnostics in
                self?.document.diagnostics = diagnostics
            }
            let text = textView.string
            let root = url.deletingLastPathComponent().path
            Task { @MainActor in
                await LSPService.shared.openDocument(language: language, uri: uri, text: text, root: root)
            }
            scheduleLSP(in: textView)
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

        private func insertSmartNewline(in textView: NSTextView) {
            let nsString = textView.string as NSString
            let selection = textView.selectedRange()
            let lineStart = nsString.lineRange(for: NSRange(location: selection.location, length: 0)).location
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

            var insertion = "\n" + indent
            if let prev = previous, bracketPairs[prev] != nil || prev == ":" {
                insertion += indentUnit
            }
            textView.insertText(insertion, replacementRange: selection)
        }
    }
}

@MainActor
private enum TextKit2SyntaxHighlighter {
    private static let maxHighlightedCharacters = 500_000

    /// Compiled-regex cache so patterns aren't rebuilt on every keystroke.
    private static var regexCache: [String: NSRegularExpression] = [:]

    private static func regex(_ pattern: String, options: NSRegularExpression.Options) -> NSRegularExpression? {
        let key = "\(options.rawValue)|\(pattern)"
        if let cached = regexCache[key] { return cached }
        guard let compiled = try? NSRegularExpression(pattern: pattern, options: options) else { return nil }
        regexCache[key] = compiled
        return compiled
    }

    /// Paints display-only color via the layout manager's *rendering attributes*,
    /// which (unlike text-storage edits) never invalidate layout — the key to
    /// flicker-free highlighting on TextKit 2.
    @MainActor
    struct RenderingPainter {
        let layoutManager: NSTextLayoutManager
        let contentManager: NSTextContentManager
        let documentStart: NSTextLocation

        init?(textView: NSTextView) {
            guard let layoutManager = textView.textLayoutManager,
                  let contentManager = layoutManager.textContentManager else { return nil }
            self.layoutManager = layoutManager
            self.contentManager = contentManager
            self.documentStart = contentManager.documentRange.location
        }

        /// Drops all color overrides so untouched tokens fall back to the storage's
        /// base foreground color.
        func reset() {
            layoutManager.invalidateRenderingAttributes(for: contentManager.documentRange)
        }

        func paint(_ attributes: [NSAttributedString.Key: Any], range: NSRange) {
            guard let start = contentManager.location(documentStart, offsetBy: range.location),
                  let end = contentManager.location(start, offsetBy: range.length),
                  let textRange = NSTextRange(location: start, end: end) else { return }
            layoutManager.setRenderingAttributes(attributes, for: textRange)
        }
    }

    /// Recolors the whole document using TextKit 2 **rendering attributes**
    /// (display-only color overrides on the layout manager) instead of mutating
    /// the text storage. Storage edits invalidate layout fragments — even for
    /// off-screen text — which made the viewport churn and the visible text
    /// flash/jitter (a line popping in and out) while typing. Rendering
    /// attributes never touch layout, so highlighting is invisible to the
    /// viewport controller: no flash, no jitter, and we can color the entire
    /// document again (correct for multi-line comments/strings).
    ///
    /// Skipped for plain text and very large files, which then render with the
    /// text view's uniform color.
    static func apply(to textView: NSTextView, language: SourceLanguage, theme: EditorTheme) {
        guard let painter = RenderingPainter(textView: textView),
              let storage = textView.textContentStorage?.textStorage else { return }
        // Clear previous colors first so removed tokens fall back to the base
        // foreground (the text storage's own color).
        painter.reset()
        let length = storage.length
        guard length > 0, length <= maxHighlightedCharacters, language != .plainText else {
            textView.typingAttributes = baseAttributes(theme: theme)
            return
        }
        let source = storage.string as NSString
        let range = NSRange(location: 0, length: length)
        // Order matters: later passes win on overlapping ranges, so tokens that
        // must always survive (strings, comments) run last.
        highlightFunctions(with: painter, source: source, range: range, language: language, color: theme.function)
        highlightTypes(with: painter, source: source, range: range, language: language, color: theme.type)
        highlightKeywords(with: painter, source: source, range: range, language: language, theme: theme)
        highlightNumbers(with: painter, source: source, range: range, color: theme.number)
        highlightPreprocessor(with: painter, source: source, range: range, language: language, color: theme.preprocessor)
        highlightStrings(with: painter, source: source, range: range, color: theme.string)
        highlightComments(with: painter, source: source, range: range, language: language, color: theme.comment)
        textView.typingAttributes = baseAttributes(theme: theme)
    }

    private static func baseAttributes(theme: EditorTheme) -> [NSAttributedString.Key: Any] {
        [
            .font: theme.nsFont,
            .foregroundColor: theme.foreground,
            .paragraphStyle: theme.paragraphStyle
        ]
    }

    private static func highlightComments(with painter: RenderingPainter, source: NSString, range: NSRange, language: SourceLanguage, color: NSColor) {
        let patterns: [String]
        switch language {
        case .markdown:
            patterns = ["<!--(?s:.*?)-->"]
        case .python, .shell, .yaml:
            patterns = ["#.*$"]
        default:
            patterns = ["//.*$", "/\\*(?s:.*?)\\*/"]
        }
        apply(patterns: patterns, with: painter, source: source, range: range, options: [.anchorsMatchLines], attributes: [.foregroundColor: color])
    }

    private static func highlightStrings(with painter: RenderingPainter, source: NSString, range: NSRange, color: NSColor) {
        apply(patterns: ["\"(?:\\\\.|[^\"\\\\])*\"", "'(?:\\\\.|[^'\\\\])*'", "<[A-Za-z0-9_./]+\\.h>"], with: painter, source: source, range: range, attributes: [.foregroundColor: color])
    }

    private static func highlightNumbers(with painter: RenderingPainter, source: NSString, range: NSRange, color: NSColor) {
        apply(patterns: ["\\b0[xX][0-9a-fA-F]+\\b", "\\b\\d+(?:\\.\\d+)?(?:[eE][-+]?\\d+)?[fFuUlL]*\\b"], with: painter, source: source, range: range, attributes: [.foregroundColor: color])
    }

    private static func highlightPreprocessor(with painter: RenderingPainter, source: NSString, range: NSRange, language: SourceLanguage, color: NSColor) {
        guard language == .c || language == .cpp else { return }
        // Color only the `#directive` token so the included path stays a string.
        applyCaptureGroup(
            pattern: "^(\\s*#\\s*(?:include|define|if|ifdef|ifndef|else|elif|endif|pragma|undef|error|warning))\\b",
            group: 1,
            with: painter,
            source: source,
            range: range,
            options: [.anchorsMatchLines],
            attributes: [.foregroundColor: color]
        )
    }

    private static func highlightFunctions(with painter: RenderingPainter, source: NSString, range: NSRange, language: SourceLanguage, color: NSColor) {
        switch language {
        case .markdown, .yaml, .json, .html, .xml, .css, .plainText:
            return
        default:
            break
        }
        applyCaptureGroup(pattern: "\\b([A-Za-z_][A-Za-z0-9_]*)\\s*(?=\\()", group: 1, with: painter, source: source, range: range, attributes: [.foregroundColor: color])
    }

    private static func highlightTypes(with painter: RenderingPainter, source: NSString, range: NSRange, language: SourceLanguage, color: NSColor) {
        switch language {
        case .markdown, .yaml, .json, .html, .xml, .css, .shell, .plainText:
            return
        default:
            break
        }
        // CamelCase identifiers (types/classes) and C `_t` suffixed types.
        apply(patterns: ["\\b[A-Z][A-Za-z0-9_]*\\b", "\\b[a-z_][A-Za-z0-9_]*_t\\b"], with: painter, source: source, range: range, attributes: [.foregroundColor: color])
    }

    private static func highlightKeywords(with painter: RenderingPainter, source: NSString, range: NSRange, language: SourceLanguage, theme: EditorTheme) {
        let (keywords, control) = keywordSets(for: language)
        if !keywords.isEmpty {
            let escaped = keywords.map(NSRegularExpression.escapedPattern(for:)).joined(separator: "|")
            apply(patterns: ["\\b(\(escaped))\\b"], with: painter, source: source, range: range, attributes: [.foregroundColor: theme.keyword])
        }
        if !control.isEmpty {
            let escaped = control.map(NSRegularExpression.escapedPattern(for:)).joined(separator: "|")
            apply(patterns: ["\\b(\(escaped))\\b"], with: painter, source: source, range: range, attributes: [.foregroundColor: theme.controlKeyword])
        }
    }

    /// Returns (declaration/storage keywords, control-flow keywords) so each
    /// group can be colored separately, mirroring VS Code's Dark+ scheme.
    private static func keywordSets(for language: SourceLanguage) -> ([String], [String]) {
        let control: [String]
        let keywords: [String]
        switch language {
        case .c, .cpp:
            control = ["break", "case", "continue", "default", "do", "else", "for", "goto", "if", "return", "switch", "while"]
            keywords = ["auto", "char", "const", "double", "enum", "extern", "float", "inline", "int", "long", "short", "signed", "sizeof", "static", "struct", "typedef", "union", "unsigned", "void", "class", "namespace", "template", "typename", "using", "public", "private", "protected", "virtual", "new", "delete", "this", "nullptr", "bool", "true", "false"]
        case .swift:
            control = ["break", "case", "catch", "continue", "default", "do", "else", "fallthrough", "for", "guard", "if", "return", "switch", "throw", "try", "while", "await"]
            keywords = ["actor", "as", "async", "class", "enum", "extension", "false", "func", "import", "in", "let", "nil", "private", "protocol", "public", "self", "static", "struct", "throws", "true", "var", "internal", "final", "override", "init", "deinit", "lazy", "weak", "some", "any"]
        case .javascript, .typescript:
            control = ["break", "case", "catch", "continue", "default", "do", "else", "for", "if", "return", "switch", "throw", "try", "while", "await", "yield"]
            keywords = ["async", "class", "const", "export", "extends", "false", "function", "import", "in", "instanceof", "let", "new", "null", "of", "static", "super", "this", "true", "type", "typeof", "var", "void", "interface", "enum", "implements"]
        case .php:
            control = ["break", "case", "continue", "default", "do", "else", "elseif", "for", "foreach", "if", "return", "switch", "while", "try", "catch", "throw"]
            keywords = ["abstract", "array", "class", "const", "echo", "extends", "false", "function", "implements", "interface", "namespace", "new", "null", "private", "protected", "public", "static", "true", "use", "var"]
        case .python:
            control = ["break", "continue", "elif", "else", "except", "finally", "for", "if", "raise", "return", "try", "while", "with", "yield", "pass"]
            keywords = ["and", "as", "async", "await", "class", "def", "False", "from", "global", "import", "in", "is", "lambda", "None", "nonlocal", "not", "or", "True"]
        case .rust:
            control = ["break", "continue", "else", "for", "if", "loop", "match", "return", "while"]
            keywords = ["as", "async", "await", "const", "crate", "enum", "false", "fn", "impl", "let", "mod", "move", "mut", "pub", "ref", "self", "static", "struct", "trait", "true", "type", "use", "where", "dyn", "Box"]
        case .go:
            control = ["break", "case", "continue", "default", "else", "fallthrough", "for", "goto", "if", "range", "return", "select", "switch"]
            keywords = ["chan", "const", "defer", "func", "go", "import", "interface", "map", "package", "struct", "type", "var", "nil", "true", "false"]
        default:
            control = []
            keywords = []
        }
        return (keywords, control)
    }

    private static func apply(patterns: [String], with painter: RenderingPainter, source: NSString, range: NSRange, options: NSRegularExpression.Options = [], attributes: [NSAttributedString.Key: Any]) {
        let text = source as String
        for pattern in patterns {
            guard let regex = regex(pattern, options: options) else { continue }
            regex.enumerateMatches(in: text, options: [], range: range) { match, _, _ in
                guard let match else { return }
                painter.paint(attributes, range: match.range)
            }
        }
    }

    private static func applyCaptureGroup(pattern: String, group: Int, with painter: RenderingPainter, source: NSString, range: NSRange, options: NSRegularExpression.Options = [], attributes: [NSAttributedString.Key: Any]) {
        guard let regex = regex(pattern, options: options) else { return }
        regex.enumerateMatches(in: source as String, options: [], range: range) { match, _, _ in
            guard let match, group < match.numberOfRanges else { return }
            let captured = match.range(at: group)
            guard captured.location != NSNotFound else { return }
            painter.paint(attributes, range: captured)
        }
    }
}
