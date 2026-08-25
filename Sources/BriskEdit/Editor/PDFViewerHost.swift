import PDFKit
import SwiftUI

/// Ships a freshly decoded, main-actor-bound object (e.g. `PDFDocument`) out of
/// a decoding task; ownership transfers to the caller.
struct DecodedObject<T>: @unchecked Sendable {
    let value: T
}

/// A lightweight, native PDF viewer backed by PDFKit's `PDFView` — continuous
/// scrolling, auto-scaling, text selection and search come for free. Documents
/// decode off the main thread; a newer request always supersedes an in-flight
/// one.
struct PDFViewerHost: NSViewRepresentable {
    let url: URL

    final class Coordinator {
        var loadedURL: URL?
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> PDFView {
        let view = PDFView()
        view.autoScales = true
        view.displayMode = .singlePageContinuous
        view.displayDirection = .vertical
        view.displaysPageBreaks = true
        view.backgroundColor = .windowBackgroundColor
        load(url, into: view, coordinator: context.coordinator)
        return view
    }

    func updateNSView(_ view: PDFView, context: Context) {
        guard context.coordinator.loadedURL != url else { return }
        load(url, into: view, coordinator: context.coordinator)
    }

    private func load(_ url: URL, into view: PDFView, coordinator: Coordinator) {
        coordinator.loadedURL = url
        view.document = nil
        Task { @MainActor [weak view] in
            let document = await Task.detached(priority: .userInitiated) {
                DecodedObject(value: PDFDocument(url: url))
            }.value.value
            guard coordinator.loadedURL == url, let view else { return }
            view.document = document
        }
    }
}
