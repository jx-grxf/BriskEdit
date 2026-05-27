import AppKit
import SwiftUI

struct EditorHost: NSViewRepresentable {
    @Bindable var document: TextDocument
    let theme: EditorTheme

    func makeNSView(context: Context) -> NSScrollView {
        let (scrollView, textView, ruler) = CodeTextView.makeScrollable(theme: theme)
        textView.string = document.text
        textView.delegate = context.coordinator
        context.coordinator.textView = textView
        context.coordinator.ruler = ruler
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let textView = scrollView.documentView as? CodeTextView else { return }
        textView.theme = theme
        context.coordinator.ruler?.setTheme(theme)
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(document: document)
    }

    @MainActor
    final class Coordinator: NSObject, NSTextViewDelegate {
        let document: TextDocument
        weak var textView: NSTextView?
        weak var ruler: LineNumberRulerView?

        init(document: TextDocument) {
            self.document = document
        }

        func textDidChange(_ notification: Notification) {
            guard let tv = notification.object as? NSTextView else { return }
            document.applyEdit(text: tv.string)
        }
    }
}
