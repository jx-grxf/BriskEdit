import AppKit

/// A lightweight, non-intrusive completion list that floats below the caret —
/// the VS Code style. It never mutates the document; it only reports the chosen
/// symbol through `onAccept` when the user confirms (Return/Tab/click). Typing,
/// arrow navigation and dismissal are driven by the editor.
@MainActor
final class CompletionPopup: NSObject, NSTableViewDataSource, NSTableViewDelegate {
    var onAccept: ((CompletionItem) -> Void)?

    private let panel: NSPanel
    private let tableView: NSTableView
    private let scrollView: NSScrollView
    private(set) var items: [CompletionItem] = []

    private let rowHeight: CGFloat = 22
    private let maxVisibleRows = 9
    private let width: CGFloat = 340

    var isVisible: Bool { panel.isVisible }
    var pageStep: Int { maxVisibleRows - 1 }

    override init() {
        panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: width, height: 100),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: true
        )
        tableView = NSTableView()
        scrollView = NSScrollView()
        super.init()

        panel.level = .floating
        panel.hasShadow = true
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hidesOnDeactivate = true
        panel.isFloatingPanel = true
        panel.becomesKeyOnlyIfNeeded = true
        panel.animationBehavior = .utilityWindow

        let background = NSVisualEffectView()
        background.material = .menu
        background.blendingMode = .behindWindow
        background.state = .active
        background.wantsLayer = true
        background.layer?.cornerRadius = 8
        background.layer?.masksToBounds = true
        background.layer?.borderWidth = 0.5
        background.layer?.borderColor = NSColor.separatorColor.cgColor

        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("symbol"))
        column.width = width - 16
        tableView.addTableColumn(column)
        tableView.headerView = nil
        tableView.backgroundColor = .clear
        tableView.rowHeight = rowHeight
        tableView.intercellSpacing = NSSize(width: 0, height: 0)
        tableView.selectionHighlightStyle = .regular
        tableView.style = .plain
        tableView.dataSource = self
        tableView.delegate = self
        tableView.target = self
        tableView.action = #selector(rowClicked)
        tableView.allowsEmptySelection = false

        scrollView.documentView = tableView
        scrollView.hasVerticalScroller = true
        scrollView.drawsBackground = false
        scrollView.borderType = .noBorder
        scrollView.automaticallyAdjustsContentInsets = false
        scrollView.contentInsets = NSEdgeInsets(top: 4, left: 0, bottom: 4, right: 0)
        scrollView.translatesAutoresizingMaskIntoConstraints = false

        background.addSubview(scrollView)
        NSLayoutConstraint.activate([
            scrollView.leadingAnchor.constraint(equalTo: background.leadingAnchor, constant: 6),
            scrollView.trailingAnchor.constraint(equalTo: background.trailingAnchor, constant: -6),
            scrollView.topAnchor.constraint(equalTo: background.topAnchor),
            scrollView.bottomAnchor.constraint(equalTo: background.bottomAnchor)
        ])
        panel.contentView = background
    }

    /// Shows / refreshes the list near the given caret rect (screen coords),
    /// constrained to the editor window so it cannot float over other apps.
    func show(items: [CompletionItem], caretScreenRect rect: NSRect, parent: NSWindow?) {
        guard let parent, parent.isVisible else {
            hide()
            return
        }
        self.items = items
        tableView.reloadData()
        if tableView.selectedRow < 0 || tableView.selectedRow >= items.count {
            tableView.selectRowIndexes([0], byExtendingSelection: false)
        }

        let visibleRows = min(items.count, maxVisibleRows)
        let height = CGFloat(visibleRows) * rowHeight + 8
        panel.setContentSize(NSSize(width: width, height: height))

        let allowedFrame = parent.contentLayoutRectInScreen.insetBy(dx: 8, dy: 8)
        let fitsBelow = rect.minY - height - 4 >= allowedFrame.minY
        let fitsAbove = rect.maxY + height + 4 <= allowedFrame.maxY

        var originY: CGFloat
        if fitsBelow || !fitsAbove {
            originY = rect.minY - height - 4
        } else {
            originY = rect.maxY + 4
        }
        var originX = rect.minX - 4
        originX = min(max(originX, allowedFrame.minX), allowedFrame.maxX - width)
        originY = min(max(originY, allowedFrame.minY), allowedFrame.maxY - height)
        panel.setFrameOrigin(NSPoint(x: originX, y: originY))

        if panel.parent !== parent {
            panel.parent?.removeChildWindow(panel)
            parent.addChildWindow(panel, ordered: .above)
        }
        if !panel.isVisible {
            panel.orderFront(nil)
        }
    }

    func hide() {
        guard panel.isVisible else { return }
        panel.orderOut(nil)
    }

    func moveSelection(by delta: Int) {
        guard !items.isEmpty else { return }
        let next = min(max(tableView.selectedRow + delta, 0), items.count - 1)
        tableView.selectRowIndexes([next], byExtendingSelection: false)
        tableView.scrollRowToVisible(next)
    }

    func moveToEdge(top: Bool) {
        guard !items.isEmpty else { return }
        let row = top ? 0 : items.count - 1
        tableView.selectRowIndexes([row], byExtendingSelection: false)
        tableView.scrollRowToVisible(row)
    }

    func acceptSelection() {
        guard items.indices.contains(tableView.selectedRow) else { hide(); return }
        let item = items[tableView.selectedRow]
        hide()
        onAccept?(item)
    }

    @objc private func rowClicked() {
        guard tableView.clickedRow >= 0 else { return }
        tableView.selectRowIndexes([tableView.clickedRow], byExtendingSelection: false)
        acceptSelection()
    }

    // MARK: - Table data

    func numberOfRows(in tableView: NSTableView) -> Int { items.count }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        let identifier = NSUserInterfaceItemIdentifier("cell")
        let cell = (tableView.makeView(withIdentifier: identifier, owner: self) as? CompletionCellView) ?? CompletionCellView(identifier: identifier)
        cell.configure(items[row])
        return cell
    }

    func tableView(_ tableView: NSTableView, rowViewForRow row: Int) -> NSTableRowView? {
        CompletionRowView()
    }
}

private extension NSWindow {
    var contentLayoutRectInScreen: NSRect {
        convertToScreen(contentLayoutRect)
    }
}

/// Cell with a kind badge, a monospaced label, and a dimmed detail hint
/// (signature/type) on the right.
private final class CompletionCellView: NSTableCellView {
    let icon = NSImageView()
    let label = NSTextField(labelWithString: "")
    let detail = NSTextField(labelWithString: "")

    init(identifier: NSUserInterfaceItemIdentifier) {
        super.init(frame: .zero)
        self.identifier = identifier

        icon.translatesAutoresizingMaskIntoConstraints = false
        icon.imageScaling = .scaleProportionallyDown
        icon.symbolConfiguration = NSImage.SymbolConfiguration(pointSize: 12, weight: .medium)
        icon.setContentHuggingPriority(.required, for: .horizontal)

        label.font = .monospacedSystemFont(ofSize: 12, weight: .regular)
        label.lineBreakMode = .byTruncatingTail
        label.translatesAutoresizingMaskIntoConstraints = false

        detail.font = .systemFont(ofSize: 10)
        detail.textColor = .secondaryLabelColor
        detail.alignment = .right
        detail.lineBreakMode = .byTruncatingTail
        detail.setContentHuggingPriority(.defaultHigh, for: .horizontal)
        detail.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        detail.translatesAutoresizingMaskIntoConstraints = false

        addSubview(icon)
        addSubview(label)
        addSubview(detail)
        textField = label
        NSLayoutConstraint.activate([
            icon.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 8),
            icon.centerYAnchor.constraint(equalTo: centerYAnchor),
            icon.widthAnchor.constraint(equalToConstant: 15),
            icon.heightAnchor.constraint(equalToConstant: 15),
            label.leadingAnchor.constraint(equalTo: icon.trailingAnchor, constant: 6),
            label.centerYAnchor.constraint(equalTo: centerYAnchor),
            detail.leadingAnchor.constraint(greaterThanOrEqualTo: label.trailingAnchor, constant: 8),
            detail.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -8),
            detail.centerYAnchor.constraint(equalTo: centerYAnchor)
        ])
    }

    func configure(_ item: CompletionItem) {
        label.stringValue = item.label
        detail.stringValue = item.detail ?? ""
        let tint = Self.tint(for: item.kind)
        icon.image = NSImage(systemSymbolName: item.kind.symbolName, accessibilityDescription: nil)
        icon.contentTintColor = tint
    }

    private static func tint(for kind: CompletionKind) -> NSColor {
        switch kind {
        case .function: .systemPurple
        case .variable: .systemTeal
        case .property: .systemTeal
        case .type: .systemOrange
        case .keyword: .systemPink
        case .constant: .systemBlue
        case .module: .systemGray
        case .snippet: .systemGreen
        case .text: .secondaryLabelColor
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }
}

/// Rounded selection highlight to match the popup chrome.
private final class CompletionRowView: NSTableRowView {
    override func drawSelection(in dirtyRect: NSRect) {
        guard isSelected else { return }
        let rect = bounds.insetBy(dx: 4, dy: 1)
        let path = NSBezierPath(roundedRect: rect, xRadius: 5, yRadius: 5)
        NSColor.controlAccentColor.withAlphaComponent(0.85).setFill()
        path.fill()
    }

    override var interiorBackgroundStyle: NSView.BackgroundStyle {
        isSelected ? .emphasized : .normal
    }
}
