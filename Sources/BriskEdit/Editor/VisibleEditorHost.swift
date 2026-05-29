import SwiftUI

struct VisibleEditorHost: View {
    @Bindable var document: TextDocument
    let theme: EditorTheme

    var body: some View {
        TextEditor(text: textBinding)
            .font(.custom(theme.fontName, size: theme.fontSize))
            .foregroundStyle(Color(nsColor: visibleForeground))
            .scrollContentBackground(.hidden)
            .background(Color(nsColor: theme.background))
            .textEditorStyle(.plain)
            .autocorrectionDisabled()
            .onAppear {
                document.updateCursor(location: document.text.utf16.count)
            }
    }

    private var textBinding: Binding<String> {
        Binding(
            get: { document.text },
            set: { newValue in
                document.applyEdit(text: newValue)
                document.updateCursor(location: newValue.utf16.count)
            }
        )
    }

    private var visibleForeground: NSColor {
        NSApp.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            ? NSColor(calibratedWhite: 0.92, alpha: 1)
            : NSColor(calibratedWhite: 0.10, alpha: 1)
    }
}
