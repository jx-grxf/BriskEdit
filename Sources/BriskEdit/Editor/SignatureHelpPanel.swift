import AppKit

/// Floating panel that shows the signature of the function call being typed,
/// with the active parameter bolded — the VS Code "parameter hints" experience.
/// Borderless and non-activating so it never steals focus from the editor.
@MainActor
final class SignatureHelpPanel {
    private var panel: NSPanel?

    var isVisible: Bool { panel?.isVisible ?? false }

    func show(signature: LSPSignatureHelp, at caretScreenRect: NSRect, theme: EditorTheme) {
        let maxWidth: CGFloat = 560
        let attributed = Self.render(signature, theme: theme)

        let label = NSTextField(labelWithAttributedString: attributed)
        label.lineBreakMode = .byWordWrapping
        label.maximumNumberOfLines = 0
        label.preferredMaxLayoutWidth = maxWidth - 20
        let labelSize = label.fittingSize
        label.frame = NSRect(x: 10, y: 8, width: min(labelSize.width, maxWidth - 20), height: labelSize.height)

        let container = NSView(frame: NSRect(x: 0, y: 0, width: label.frame.width + 20, height: label.frame.height + 16))
        container.wantsLayer = true
        container.layer?.backgroundColor = theme.background.blended(withFraction: 0.12, of: .white)?.cgColor ?? theme.background.cgColor
        container.layer?.borderColor = theme.foreground.withAlphaComponent(0.18).cgColor
        container.layer?.borderWidth = 1
        container.layer?.cornerRadius = 6
        container.addSubview(label)

        let panel = self.panel ?? makePanel()
        panel.setContentSize(container.frame.size)
        panel.contentView = container

        // Place above the caret; flip below only if it would clip the screen top.
        var origin = NSPoint(x: caretScreenRect.minX, y: caretScreenRect.maxY + 6)
        if let screen = NSScreen.main, origin.y + container.frame.height > screen.visibleFrame.maxY {
            origin.y = caretScreenRect.minY - container.frame.height - 6
        }
        panel.setFrameOrigin(origin)
        panel.orderFront(nil)
        self.panel = panel
    }

    func hide() {
        panel?.orderOut(nil)
    }

    private func makePanel() -> NSPanel {
        let panel = NSPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: true)
        panel.isFloatingPanel = true
        panel.level = .floating
        panel.hasShadow = true
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hidesOnDeactivate = true
        panel.ignoresMouseEvents = true
        return panel
    }

    /// Builds the signature string: the whole label dimmed, the active parameter
    /// span bolded and tinted, with an optional "1/2" overload counter prefix.
    private static func render(_ help: LSPSignatureHelp, theme: EditorTheme) -> NSAttributedString {
        let size: CGFloat = 12
        let base = NSFont.monospacedSystemFont(ofSize: size, weight: .regular)
        let bold = NSFont.monospacedSystemFont(ofSize: size, weight: .bold)
        let dim = theme.foreground.withAlphaComponent(0.75)

        let result = NSMutableAttributedString()
        guard !help.signatures.isEmpty else { return result }
        let activeSignature = min(max(help.activeSignature, 0), help.signatures.count - 1)
        let signature = help.signatures[activeSignature]

        if help.signatures.count > 1 {
            result.append(NSAttributedString(string: "\(activeSignature + 1)/\(help.signatures.count)  ", attributes: [
                .font: base,
                .foregroundColor: theme.foreground.withAlphaComponent(0.45)
            ]))
        }

        let label = NSMutableAttributedString(string: signature.label, attributes: [
            .font: base,
            .foregroundColor: dim
        ])
        let ns = signature.label as NSString
        if signature.parameters.indices.contains(help.activeParameter) {
            let param = signature.parameters[help.activeParameter]
            let range = NSRange(location: param.start, length: param.length)
            if range.location >= 0, NSMaxRange(range) <= ns.length, range.length > 0 {
                label.addAttributes([.font: bold, .foregroundColor: theme.function], range: range)
            }
        }
        result.append(label)
        return result
    }
}
