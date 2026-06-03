import AppKit
import SwiftUI

/// A lightweight image viewer for raster formats (PNG, JPEG, GIF, HEIC, …). The
/// image is scaled proportionally to fit the pane and re-centered, so it works
/// both as a full editor tab and inside the resizable split-preview pane. Read
/// only — BriskEdit never writes image files back.
struct ImageViewerHost: NSViewRepresentable {
    let url: URL

    func makeNSView(context: Context) -> NSView {
        let container = NSView()
        container.wantsLayer = true

        let imageView = NSImageView()
        imageView.imageScaling = .scaleProportionallyUpOrDown
        imageView.imageAlignment = .alignCenter
        imageView.imageFrameStyle = .none
        imageView.animates = true // play animated GIFs
        imageView.image = NSImage(contentsOf: url)
        imageView.translatesAutoresizingMaskIntoConstraints = false

        container.addSubview(imageView)
        NSLayoutConstraint.activate([
            imageView.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 12),
            imageView.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -12),
            imageView.topAnchor.constraint(equalTo: container.topAnchor, constant: 12),
            imageView.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -12)
        ])
        context.coordinator.imageView = imageView
        context.coordinator.loadedURL = url
        return container
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        guard context.coordinator.loadedURL != url else { return }
        context.coordinator.loadedURL = url
        context.coordinator.imageView?.image = NSImage(contentsOf: url)
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    final class Coordinator {
        var imageView: NSImageView?
        var loadedURL: URL?
    }
}
