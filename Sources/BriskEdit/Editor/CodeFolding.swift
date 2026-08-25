import AppKit

/// One foldable region, detected purely from indentation (zero-config, language
/// agnostic — a plain indentation folding provider). Lines are 0-based
/// indices into the document's line list.
struct FoldRegion: Equatable {
    /// The line whose chevron toggles the fold (the "header"); stays visible.
    let headerLine: Int
    /// The last line that belongs to the region; everything from `headerLine + 1`
    /// through `lastLine` is hidden when folded.
    let lastLine: Int
    /// UTF-16 character range covering the hidden paragraphs (header excluded).
    let hiddenRange: NSRange
}

enum FoldingRefreshPolicy {
    static func needsRecompute(
        previousTheme: EditorTheme,
        theme: EditorTheme,
        languageChanged: Bool,
        documentReseeded: Bool
    ) -> Bool {
        documentReseeded
            || languageChanged
            || previousTheme.showCodeFolding != theme.showCodeFolding
            || previousTheme.tabWidth != theme.tabWidth
    }
}

/// Detects foldable regions by indentation. A line is a fold header when the
/// next non-blank line is indented deeper; the region runs until indentation
/// returns to the header's level (blank lines in between stay inside it).
enum FoldingAnalyzer {
    static func regions(in text: NSString, tabWidth: Int) -> [FoldRegion] {
        guard text.length > 0 else { return [] }

        // Collect each line's paragraph range (incl. trailing newline), its indent
        // width, whether it's blank, and whether it trims to a lone closer or a
        // bare `{` — classified in place over UTF-16, without materializing a
        // trimmed string per line.
        var ranges: [NSRange] = []
        var indents: [Int] = []
        var blanks: [Bool] = []
        var loneClosers: [Bool] = []
        var bareOpeners: [Bool] = []
        text.enumerateSubstrings(in: NSRange(location: 0, length: text.length), options: [.byLines, .substringNotRequired]) { _, _, enclosing, _ in
            ranges.append(enclosing)
            var end = NSMaxRange(enclosing)
            while end > enclosing.location {
                let c = text.character(at: end - 1)
                if c == 0x0A || c == 0x0D { end -= 1 } else { break }
            }
            let line = Self.classifyLine(text, from: enclosing.location, upTo: end, tabWidth: tabWidth)
            indents.append(line.indent)
            blanks.append(line.blank)
            loneClosers.append(line.closer)
            bareOpeners.append(line.bareOpener)
        }

        var regions: [FoldRegion] = []
        var claimedHeaders = Set<Int>()
        for i in 0..<ranges.count where !blanks[i] {
            let base = indents[i]
            var last = i
            var k = i + 1
            while k < ranges.count {
                if blanks[k] { k += 1; continue }      // blanks belong to the region
                if indents[k] > base { last = k; k += 1 } else { break }
            }
            guard last > i else { continue }

            // Absorb a trailing lone closing delimiter (`}`, `};`, `)`, `]`…) that
            // sits at the header's indent — pure-indentation folding excludes it,
            // which left the closing brace dangling on its own line after a fold.
            if last + 1 < ranges.count, !blanks[last + 1],
               indents[last + 1] <= base, loneClosers[last + 1] {
                last += 1
            }

            // If the fold header is a bare opening brace (Allman style), promote it
            // to the preceding signature/control line so the whole block collapses
            // to one clean header line instead of leaving `{` stranded above the
            // hidden body. Guard against stealing a line already used as a header.
            var header = i
            if bareOpeners[i], i - 1 >= 0, !blanks[i - 1],
               indents[i - 1] <= base, !claimedHeaders.contains(i - 1),
               !regions.contains(where: { $0.lastLine >= i - 1 && $0.headerLine < i - 1 }) {
                header = i - 1
            }

            claimedHeaders.insert(header)
            let start = ranges[header + 1].location
            let end = NSMaxRange(ranges[last])
            regions.append(FoldRegion(headerLine: header, lastLine: last, hiddenRange: NSRange(location: start, length: end - start)))
        }
        return regions
    }

    /// Classifies one line in place over UTF-16 (no trimmed-string copies):
    /// leading-whitespace width (tabs counted as `tabWidth`), whether the line
    /// is blank, whether it trims to a lone closing delimiter (optionally with
    /// trailing `;` or `,`, e.g. `}`, `};`, `)`, `},`), and whether it trims to
    /// exactly `{`.
    private static func classifyLine(_ text: NSString, from start: Int, upTo end: Int, tabWidth: Int)
        -> (indent: Int, blank: Bool, closer: Bool, bareOpener: Bool) {
        let openBrace = unichar(UnicodeScalar("{").value)
        let closeBrace = unichar(UnicodeScalar("}").value)
        let closeBracket = unichar(UnicodeScalar("]").value)
        let closeParen = unichar(UnicodeScalar(")").value)
        let semicolon = unichar(UnicodeScalar(";").value)
        let comma = unichar(UnicodeScalar(",").value)

        var indent = 0
        var i = start
        while i < end {
            let c = text.character(at: i)
            if c == 0x20 { indent += 1 }
            else if c == 0x09 { indent += tabWidth }
            else { break }
            i += 1
        }
        guard i < end else { return (indent, true, false, false) }

        let first = text.character(at: i)
        var j = end - 1
        while j > i {
            let c = text.character(at: j)
            if c != 0x20 && c != 0x09 { break }
            j -= 1
        }
        let last = text.character(at: j)

        func isCloserToken(_ c: unichar) -> Bool {
            c == closeBrace || c == closeBracket || c == closeParen || c == semicolon || c == comma
        }
        var closer = first == closeBrace || first == closeBracket || first == closeParen
        if closer {
            var k = i
            while k <= j {
                let c = text.character(at: k)
                if c != 0x20 && c != 0x09 && !isCloserToken(c) { closer = false; break }
                k += 1
            }
        }
        // Exactly `{`: the only non-whitespace character sits at `i == j`.
        let bareOpener = first == openBrace && last == openBrace && i == j
        return (indent, false, closer, bareOpener)
    }
}

/// Collapses folded paragraphs to ~zero height via the content-storage delegate.
/// This is display-only: it returns substitute `NSTextParagraph`s with a
/// near-zero line height and clear color, **without** mutating the text storage
/// — so it respects "TextDocument is the only writer of its text" and never
/// touches the layout the way an `NSRulerView` would. The header line stays
/// fully visible; only the lines beneath a collapsed region shrink away.
///
/// `@unchecked Sendable`: every entry point (the editor coordinator, the gutter,
/// and TextKit's delegate callback) runs on the main thread, so the mutable
/// state is never touched concurrently. The conformance can't be main-actor
/// isolated because `NSTextContentStorageDelegate` is not.
final class FoldingController: NSObject, NSTextContentStorageDelegate, @unchecked Sendable {
    /// All foldable regions for the current text, keyed by header line.
    private(set) var regions: [FoldRegion] = []
    /// Header lines the user has collapsed.
    private(set) var foldedHeaderLines: Set<Int> = []
    /// Merged hidden character ranges for the currently-folded regions.
    private var hiddenRanges: [NSRange] = []

    weak var contentStorage: NSTextContentStorage?
    /// The text view that renders this content, so a relayout can force the
    /// viewport to re-lay-out and repaint — TextKit 2 otherwise leaves stale or
    /// black fragments behind until a scroll/resize nudges it.
    weak var textView: NSTextView?

    var hasRegions: Bool { !regions.isEmpty }

    func isFolded(headerLine: Int) -> Bool { foldedHeaderLines.contains(headerLine) }

    func region(forHeaderLine line: Int) -> FoldRegion? {
        regions.first { $0.headerLine == line }
    }

    /// Whether a 0-based line sits inside a currently-folded region (below its
    /// header) — i.e. it's collapsed and the gutter should not number it.
    func isHidden(lineIndex0 line: Int) -> Bool {
        for header in foldedHeaderLines {
            if let r = region(forHeaderLine: header), line > r.headerLine, line <= r.lastLine {
                return true
            }
        }
        return false
    }

    /// Recomputes regions after an edit. Drops folds whose header is no longer a
    /// region; keeps the rest folded.
    func updateRegions(_ newRegions: [FoldRegion]) {
        regions = newRegions
        let validHeaders = Set(newRegions.map(\.headerLine))
        foldedHeaderLines.formIntersection(validHeaders)
        let previous = hiddenRanges
        recomputeHidden()
        // Only disturb the layout when the *hidden* set actually changed. With a
        // fold active but unaffected by the edit (e.g. typing below it) the ranges
        // are identical, so plain typing never triggers a (full-document) relayout
        // — the source of the black-line / jumping artifacts.
        guard hiddenRanges != previous else { return }
        relayout(invalidatingFrom: Self.earliestDivergence(previous, hiddenRanges))
    }

    /// Toggles a region's folded state and re-lays out the affected text.
    func toggle(headerLine: Int) {
        guard let region = region(forHeaderLine: headerLine) else { return }
        if foldedHeaderLines.contains(headerLine) {
            foldedHeaderLines.remove(headerLine)
        } else {
            foldedHeaderLines.insert(headerLine)
        }
        recomputeHidden()
        // Everything from the toggled region's header downward shifts; nothing
        // above it moves, so the relayout can start there.
        relayout(invalidatingFrom: region.hiddenRange.location)
    }

    func unfoldAll() {
        guard !foldedHeaderLines.isEmpty else { return }
        let from = hiddenRanges.first?.location ?? 0
        foldedHeaderLines.removeAll()
        recomputeHidden()
        relayout(invalidatingFrom: from)
    }

    /// The first character location where two sorted hidden-range lists diverge;
    /// everything below it may shift, everything above is untouched.
    private static func earliestDivergence(_ a: [NSRange], _ b: [NSRange]) -> Int {
        for i in 0..<max(a.count, b.count) {
            let lhs = i < a.count ? a[i] : nil
            let rhs = i < b.count ? b[i] : nil
            if lhs?.location != rhs?.location || lhs?.length != rhs?.length {
                return min(lhs?.location ?? .max, rhs?.location ?? .max)
            }
        }
        return 0
    }

    private func recomputeHidden() {
        hiddenRanges = foldedHeaderLines
            .compactMap { region(forHeaderLine: $0)?.hiddenRange }
            .sorted { $0.location < $1.location }
    }

    /// Forces the content storage to rebuild its paragraphs so the delegate runs
    /// again with the new hidden set. An attribute-only edit (no length change)
    /// invalidates the cached text elements without altering the stored text.
    ///
    /// The invalidation starts at `start` (not always 0): only text from the
    /// first changed fold downward can shift, so re-laying out the whole document
    /// on every toggle/recompute is what produced the visible black/jumping
    /// fragments. After the edit we explicitly drive a viewport layout + repaint,
    /// because TextKit 2 otherwise leaves stale fragments until a scroll nudge.
    private func relayout(invalidatingFrom start: Int) {
        guard let contentStorage, let storage = contentStorage.textStorage, storage.length > 0 else { return }
        let location = max(0, min(start, storage.length))
        contentStorage.performEditingTransaction {
            storage.edited(.editedAttributes, range: NSRange(location: location, length: storage.length - location), changeInLength: 0)
        }
        contentStorage.primaryTextLayoutManager?.textViewportLayoutController.layoutViewport()
        DispatchQueue.main.async { [weak self] in
            self?.textView?.needsDisplay = true
        }
    }

    // MARK: - NSTextContentStorageDelegate

    func textContentStorage(_ textContentStorage: NSTextContentStorage, textParagraphWith range: NSRange) -> NSTextParagraph? {
        guard !hiddenRanges.isEmpty,
              hiddenRanges.contains(where: { NSLocationInRange(range.location, $0) }),
              let original = textContentStorage.textStorage?.attributedSubstring(from: range) else { return nil }
        let collapsed = NSMutableAttributedString(attributedString: original)
        let style = NSMutableParagraphStyle()
        style.maximumLineHeight = 0.1
        style.minimumLineHeight = 0.1
        style.lineSpacing = 0
        style.paragraphSpacing = 0
        style.paragraphSpacingBefore = 0
        collapsed.addAttributes(
            [.paragraphStyle: style,
             .font: NSFont.systemFont(ofSize: 0.1),
             .foregroundColor: NSColor.clear],
            range: NSRange(location: 0, length: collapsed.length)
        )
        return NSTextParagraph(attributedString: collapsed)
    }
}
