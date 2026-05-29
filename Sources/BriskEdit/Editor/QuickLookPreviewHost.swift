import QuickLookUI
import SwiftUI

/// Embeds macOS Quick Look for document formats that do not have a dedicated
/// editor surface in BriskEdit, such as Word `.docx` files.
struct QuickLookPreviewHost: NSViewRepresentable {
    let url: URL

    func makeNSView(context: Context) -> QLPreviewView {
        let view = QLPreviewView(frame: .zero, style: .normal)!
        view.autostarts = true
        view.previewItem = url as NSURL
        return view
    }

    func updateNSView(_ view: QLPreviewView, context: Context) {
        if view.previewItem?.previewItemURL != url {
            view.previewItem = url as NSURL
            view.refreshPreviewItem()
        }
    }
}
