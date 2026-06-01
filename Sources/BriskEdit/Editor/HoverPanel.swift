import AppKit

/// Small floating panel that shows LSP hover text (type/signature/docs) near the
/// symbol under the cursor. Borderless and non-activating so it never steals
/// focus from the editor.
@MainActor
final class HoverPanel {
    private var panel: NSPanel?

    func show(text: String, at screenRect: NSRect, theme: EditorTheme) {
        let maxWidth: CGFloat = 460
        let label = NSTextField(wrappingLabelWithString: trimmed(text))
        label.font = .monospacedSystemFont(ofSize: 11, weight: .regular)
        label.textColor = theme.foreground
        label.preferredMaxLayoutWidth = maxWidth - 20
        label.lineBreakMode = .byWordWrapping
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

        // Place above the symbol; flip below if it would clip the screen top.
        var origin = NSPoint(x: screenRect.minX, y: screenRect.maxY + 6)
        if let screen = NSScreen.main, origin.y + container.frame.height > screen.visibleFrame.maxY {
            origin.y = screenRect.minY - container.frame.height - 6
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

    /// LSP hover is often Markdown; strip code fences so it reads cleanly in a
    /// plain label (full Markdown rendering would be overkill for a tooltip).
    private func trimmed(_ text: String) -> String {
        let cleaned = text
            .replacingOccurrences(of: "```", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let lines = cleaned.split(separator: "\n", omittingEmptySubsequences: false).prefix(20)
        return lines.joined(separator: "\n")
    }
}
