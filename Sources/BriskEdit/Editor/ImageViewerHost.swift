import AppKit
import SwiftUI

/// Interactive raster image viewer used by full tabs and split previews.
/// Images start fitted to the available pane; users can zoom, pinch and pan.
struct ImageViewerHost: NSViewRepresentable {
    let url: URL

    func makeNSView(context: Context) -> InteractiveImageView {
        let view = InteractiveImageView()
        view.load(url)
        return view
    }

    func updateNSView(_ view: InteractiveImageView, context: Context) {
        guard view.loadedURL != url else { return }
        view.load(url)
    }
}

@MainActor
final class InteractiveImageView: NSView {
    private let scrollView = NSScrollView()
    private let imageView = NSImageView()
    private let zoomLabel = NSTextField(labelWithString: "100%")
    private var fitMode = true
    private var lastViewportSize = NSSize.zero
    private var isUpdatingZoom = false
    private(set) var loadedURL: URL?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true

        let controls = makeControls()
        controls.translatesAutoresizingMaskIntoConstraints = false

        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.drawsBackground = false
        scrollView.borderType = .noBorder
        scrollView.hasHorizontalScroller = true
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.allowsMagnification = true
        scrollView.minMagnification = 0.01
        scrollView.maxMagnification = 8
        scrollView.contentView = CenteringClipView()

        imageView.imageScaling = .scaleNone
        imageView.imageAlignment = .alignCenter
        imageView.imageFrameStyle = .none
        imageView.animates = true
        scrollView.documentView = imageView

        addSubview(controls)
        addSubview(scrollView)
        NSLayoutConstraint.activate([
            controls.leadingAnchor.constraint(equalTo: leadingAnchor),
            controls.trailingAnchor.constraint(equalTo: trailingAnchor),
            controls.topAnchor.constraint(equalTo: topAnchor),
            controls.heightAnchor.constraint(equalToConstant: 32),
            scrollView.leadingAnchor.constraint(equalTo: leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: trailingAnchor),
            scrollView.topAnchor.constraint(equalTo: controls.bottomAnchor),
            scrollView.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(liveMagnificationEnded),
            name: NSScrollView.didEndLiveMagnifyNotification,
            object: scrollView
        )
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    override func layout() {
        super.layout()
        let viewportSize = scrollView.contentSize
        guard viewportSize.width > 0, viewportSize.height > 0,
              viewportSize != lastViewportSize else { return }
        lastViewportSize = viewportSize
        if fitMode {
            fitImage()
        }
    }

    func load(_ url: URL) {
        loadedURL = url
        imageView.image = NSImage(contentsOf: url)
        if let size = imageView.image?.size, size.width > 0, size.height > 0 {
            imageView.frame = NSRect(origin: .zero, size: size)
        } else {
            imageView.frame = .zero
        }
        fitMode = true
        lastViewportSize = .zero
        needsLayout = true
    }

    private func makeControls() -> NSView {
        let background = NSVisualEffectView()
        background.material = .headerView
        background.blendingMode = .withinWindow

        let zoomOut = button(symbol: "minus.magnifyingglass", label: "Zoom Out", action: #selector(zoomOut))
        let zoomIn = button(symbol: "plus.magnifyingglass", label: "Zoom In", action: #selector(zoomIn))
        let actualSize = button(symbol: "1.magnifyingglass", label: "Actual Size", action: #selector(showActualSize))
        let fit = button(symbol: "arrow.down.right.and.arrow.up.left", label: "Fit Image", action: #selector(fitImageAction))

        zoomLabel.font = .monospacedDigitSystemFont(ofSize: NSFont.smallSystemFontSize, weight: .regular)
        zoomLabel.textColor = .secondaryLabelColor
        zoomLabel.alignment = .center
        zoomLabel.setContentHuggingPriority(.required, for: .horizontal)

        let stack = NSStackView(views: [zoomOut, zoomLabel, zoomIn, actualSize, fit])
        stack.orientation = .horizontal
        stack.alignment = .centerY
        stack.spacing = 6
        stack.translatesAutoresizingMaskIntoConstraints = false
        background.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.centerXAnchor.constraint(equalTo: background.centerXAnchor),
            stack.centerYAnchor.constraint(equalTo: background.centerYAnchor),
            zoomLabel.widthAnchor.constraint(greaterThanOrEqualToConstant: 44)
        ])
        return background
    }

    private func button(symbol: String, label: String, action: Selector) -> NSButton {
        let image = NSImage(systemSymbolName: symbol, accessibilityDescription: label) ?? NSImage()
        let button = NSButton(image: image, target: self, action: action)
        button.bezelStyle = .accessoryBarAction
        button.isBordered = false
        button.toolTip = label
        button.setAccessibilityLabel(label)
        return button
    }

    @objc private func zoomOut() {
        setZoom(scrollView.magnification / 1.25)
    }

    @objc private func zoomIn() {
        setZoom(scrollView.magnification * 1.25)
    }

    @objc private func showActualSize() {
        setZoom(1)
    }

    @objc private func fitImageAction() {
        fitMode = true
        fitImage()
    }

    @objc private func liveMagnificationEnded() {
        fitMode = false
        updateZoomLabel()
    }

    private func fitImage() {
        guard !isUpdatingZoom, let imageSize = imageView.image?.size else { return }
        let zoom = ImageViewerLayout.fitMagnification(
            imageSize: imageSize,
            viewportSize: scrollView.contentSize,
            minimum: scrollView.minMagnification,
            maximum: scrollView.maxMagnification
        )
        setZoom(zoom, keepsFitMode: true)
    }

    private func setZoom(_ value: CGFloat, keepsFitMode: Bool = false) {
        guard imageView.image != nil else { return }
        isUpdatingZoom = true
        defer { isUpdatingZoom = false }
        fitMode = keepsFitMode
        let zoom = min(max(value, scrollView.minMagnification), scrollView.maxMagnification)
        let visibleCenter = NSPoint(x: scrollView.contentView.bounds.midX, y: scrollView.contentView.bounds.midY)
        scrollView.setMagnification(zoom, centeredAt: visibleCenter)
        updateZoomLabel()
    }

    private func updateZoomLabel() {
        zoomLabel.stringValue = "\(Int((scrollView.magnification * 100).rounded()))%"
    }
}

private final class CenteringClipView: NSClipView {
    override func constrainBoundsRect(_ proposedBounds: NSRect) -> NSRect {
        var bounds = super.constrainBoundsRect(proposedBounds)
        guard let documentView else { return bounds }
        if documentView.frame.width < bounds.width {
            bounds.origin.x = (documentView.frame.width - bounds.width) / 2
        }
        if documentView.frame.height < bounds.height {
            bounds.origin.y = (documentView.frame.height - bounds.height) / 2
        }
        return bounds
    }
}

enum ImageViewerLayout {
    static func fitMagnification(
        imageSize: NSSize,
        viewportSize: NSSize,
        minimum: CGFloat = 0.01,
        maximum: CGFloat = 8
    ) -> CGFloat {
        guard imageSize.width > 0, imageSize.height > 0,
              viewportSize.width > 0, viewportSize.height > 0 else { return 1 }
        let fit = min(viewportSize.width / imageSize.width, viewportSize.height / imageSize.height)
        return min(max(fit, minimum), maximum)
    }
}
