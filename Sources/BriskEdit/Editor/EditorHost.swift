import AppKit
import SwiftUI

struct EditorHost: NSViewRepresentable {
    @Bindable var document: TextDocument
    let theme: EditorTheme

    func makeNSView(context: Context) -> NSScrollView {
        let (scrollView, textView, ruler) = CodeTextView.makeScrollable(theme: theme)
        textView.delegate = context.coordinator
        textView.language = document.language

        context.coordinator.textView = textView
        context.coordinator.scrollView = scrollView
        context.coordinator.ruler = ruler
        context.coordinator.theme = theme
        textView.replaceTextIfNeeded(document.text)

        DispatchQueue.main.async { [weak scrollView, weak textView] in
            scrollView?.window?.makeFirstResponder(textView)
        }
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let textView = context.coordinator.textView else { return }
        let coord = context.coordinator
        coord.document = document
        coord.theme = theme

        if textView.theme != theme {
            textView.theme = theme
            coord.ruler?.setTheme(theme)
        }
        textView.language = document.language
        textView.replaceTextIfNeeded(document.text)
    }

    func makeCoordinator() -> Coordinator { Coordinator(document: document, theme: theme) }

    @MainActor
    final class Coordinator: NSObject, NSTextViewDelegate {
        var document: TextDocument
        var theme: EditorTheme
        weak var textView: CodeTextView?
        weak var scrollView: NSScrollView?
        weak var ruler: LineNumberRulerView?
        private var highlightWork: DispatchWorkItem?

        init(document: TextDocument, theme: EditorTheme) {
            self.document = document
            self.theme = theme
        }

        func textDidChange(_ notification: Notification) {
            guard let tv = notification.object as? NSTextView else { return }
            document.applyEdit(text: tv.string)
            scheduleHighlight()
        }

        func textViewDidChangeSelection(_ notification: Notification) {
            guard let tv = notification.object as? NSTextView else { return }
            document.updateCursor(location: tv.selectedRange().location)
        }

        private func scheduleHighlight() {
            highlightWork?.cancel()
            let lang = document.language
            let currentTheme = theme
            let work = DispatchWorkItem { [weak textView] in
                guard let textView else { return }
                SyntaxHighlighter.apply(to: textView, language: lang, theme: currentTheme)
            }
            highlightWork = work
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.12, execute: work)
        }

        func textView(_ textView: NSTextView, shouldChangeTextIn range: NSRange, replacementString: String?) -> Bool {
            guard let s = replacementString, range.length == 0, s.count == 1 else { return true }
            let pairs: [Character: Character] = ["{": "}", "(": ")", "[": "]", "\"": "\"", "'": "'"]
            guard let opener = s.first, let closer = pairs[opener] else { return true }
            textView.insertText("\(opener)\(closer)", replacementRange: range)
            textView.setSelectedRange(NSRange(location: range.location + 1, length: 0))
            return false
        }

        func textView(_ textView: NSTextView, doCommandBy selector: Selector) -> Bool {
            switch selector {
            case #selector(NSResponder.insertTab(_:)):
                handleTab(in: textView, outdent: false)
                return true
            case #selector(NSResponder.insertBacktab(_:)):
                handleTab(in: textView, outdent: true)
                return true
            case #selector(NSResponder.insertNewline(_:)):
                handleNewline(in: textView)
                return true
            default:
                return false
            }
        }

        private var indentUnit: String {
            theme.usesSpacesForTabs ? String(repeating: " ", count: theme.tabWidth) : "\t"
        }

        private func handleTab(in textView: NSTextView, outdent: Bool) {
            let nsString = textView.string as NSString
            let selRange = textView.selectedRange()
            let lineRange = nsString.lineRange(for: selRange)
            let hasSelection = selRange.length > 0
            let unit = indentUnit
            if hasSelection || outdent {
                let block = nsString.substring(with: lineRange)
                let lines = block.split(separator: "\n", omittingEmptySubsequences: false)
                let transformed: [String] = lines.map { line in
                    let s = String(line)
                    if outdent {
                        if s.hasPrefix(unit) { return String(s.dropFirst(unit.count)) }
                        if s.hasPrefix("\t") { return String(s.dropFirst()) }
                        var i = s.startIndex
                        var dropped = 0
                        while dropped < theme.tabWidth, i < s.endIndex, s[i] == " " {
                            i = s.index(after: i); dropped += 1
                        }
                        return String(s[i...])
                    } else {
                        return unit + s
                    }
                }
                let replacement = transformed.joined(separator: "\n")
                if textView.shouldChangeText(in: lineRange, replacementString: replacement) {
                    textView.replaceCharacters(in: lineRange, with: replacement)
                    textView.didChangeText()
                    let newLen = (replacement as NSString).length
                    textView.setSelectedRange(NSRange(location: lineRange.location, length: newLen))
                }
            } else {
                textView.insertText(unit, replacementRange: selRange)
            }
        }

        private func handleNewline(in textView: NSTextView) {
            let nsString = textView.string as NSString
            let selRange = textView.selectedRange()
            let lineStart = nsString.lineRange(for: NSRange(location: selRange.location, length: 0)).location
            var idx = lineStart
            var indent = ""
            while idx < selRange.location {
                let scalar = UnicodeScalar(nsString.character(at: idx))!
                if scalar == " " || scalar == "\t" {
                    indent.append(Character(scalar))
                    idx += 1
                } else { break }
            }
            var extraIndent = ""
            if selRange.location > 0 {
                let prev = nsString.character(at: selRange.location - 1)
                if let s = UnicodeScalar(prev), (s == "{" || s == "(" || s == "[" || s == ":") {
                    extraIndent = indentUnit
                }
            }
            var insertion = "\n" + indent + extraIndent
            var cursorAfter = (insertion as NSString).length
            if selRange.location > 0, selRange.location < nsString.length {
                let prev = nsString.character(at: selRange.location - 1)
                let next = nsString.character(at: selRange.location)
                let pairs: [(unichar, unichar)] = [
                    (unichar(("{" as Character).asciiValue!), unichar(("}" as Character).asciiValue!)),
                    (unichar(("(" as Character).asciiValue!), unichar((")" as Character).asciiValue!)),
                    (unichar(("[" as Character).asciiValue!), unichar(("]" as Character).asciiValue!))
                ]
                if pairs.contains(where: { $0.0 == prev && $0.1 == next }) {
                    insertion = "\n" + indent + extraIndent + "\n" + indent
                    cursorAfter = ("\n" + indent + extraIndent as NSString).length
                }
            }
            if textView.shouldChangeText(in: selRange, replacementString: insertion) {
                textView.replaceCharacters(in: selRange, with: insertion)
                textView.didChangeText()
                textView.setSelectedRange(NSRange(location: selRange.location + cursorAfter, length: 0))
            }
        }
    }
}
