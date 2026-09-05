import AppKit
import SwiftUI

struct ComparisonView: View {
    @Bindable var review: WorkspaceReviewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label(review.comparisonTitle, systemImage: "rectangle.split.2x1")
                    .font(.headline).lineLimit(2)
                Spacer()
                Button("Done") { review.showComparison = false }.keyboardShortcut(.cancelAction)
            }
            Text("Read-only snapshot. − removed from the left side; + added on the right side.")
                .font(.caption).foregroundStyle(.secondary)
            Divider()
            if review.comparisonLoading {
                ProgressView("Comparing…").frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let error = review.comparisonError {
                ContentUnavailableView("Could Not Compare", systemImage: "exclamationmark.triangle",
                                       description: Text(error))
            } else if review.comparisonText.isEmpty {
                ContentUnavailableView("No Changes", systemImage: "checkmark.circle")
            } else {
                ReadOnlyTextView(text: review.comparisonText, highlightsDiff: true)
            }
        }
        .padding(20).frame(minWidth: 640, idealWidth: 860, minHeight: 420, idealHeight: 600)
        .background(.background)
        .onDisappear { review.cancelComparison() }
    }
}

struct ReferencesView: View {
    let workspace: WorkspaceModel
    @State private var selection: ReferenceResult.ID?

    var body: some View {
        @Bindable var review = workspace.review
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label(review.referenceTitle, systemImage: "arrow.triangle.branch").font(.headline)
                Spacer()
                Button("Done") { review.showReferences = false }.keyboardShortcut(.cancelAction)
            }
            if review.referencesLoading {
                ProgressView("Finding references…").frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let error = review.referencesError {
                ContentUnavailableView("Could Not Find References", systemImage: "exclamationmark.triangle",
                                       description: Text(error))
            } else if review.references.isEmpty {
                ContentUnavailableView("No References", systemImage: "text.magnifyingglass")
            } else {
                Text("\(review.references.count) references").font(.caption).foregroundStyle(.secondary)
                List(review.references, selection: $selection) { result in
                    Button { open(result) } label: {
                        VStack(alignment: .leading, spacing: 3) {
                            Text("\(result.url.lastPathComponent):\(result.line):\(result.column)")
                                .font(.system(.body, design: .monospaced))
                            Text(result.url.deletingLastPathComponent().path)
                                .font(.caption).foregroundStyle(.secondary).lineLimit(1).truncationMode(.head)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading).contentShape(Rectangle())
                    }
                    .buttonStyle(.plain).tag(result.id)
                }
                Button("Open Reference") {
                    if let result = review.references.first(where: { $0.id == selection }) { open(result) }
                }
                .keyboardShortcut(.defaultAction).disabled(selection == nil)
            }
        }
        .padding(20).frame(minWidth: 580, idealWidth: 720, minHeight: 400, idealHeight: 520)
        .background(.background)
        .onChange(of: review.references, initial: true) { _, references in
            if selection == nil { selection = references.first?.id }
        }
        .onDisappear { workspace.review.cancelReferences() }
    }

    private func open(_ result: ReferenceResult) {
        workspace.review.showReferences = false
        Task { await workspace.openFile(at: result.url, line: result.line, column: result.column) }
    }
}

struct ReadOnlyTextView: NSViewRepresentable {
    let text: String
    var highlightsDiff = false

    func makeNSView(context: Context) -> NSScrollView {
        let scroll = NSScrollView()
        scroll.hasVerticalScroller = true
        scroll.hasHorizontalScroller = true
        let view = NSTextView()
        view.isEditable = false
        view.isSelectable = true
        view.isRichText = false
        view.font = .monospacedSystemFont(ofSize: 12, weight: .regular)
        view.textColor = .textColor
        view.backgroundColor = .textBackgroundColor
        view.textContainerInset = NSSize(width: 10, height: 10)
        view.isVerticallyResizable = true
        view.isHorizontallyResizable = true
        view.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        view.textContainer?.containerSize = view.maxSize
        view.textContainer?.widthTracksTextView = false
        view.setAccessibilityLabel(highlightsDiff ? "Read-only unified diff" : "Read-only recovered draft")
        scroll.documentView = view
        return scroll
    }

    func updateNSView(_ scroll: NSScrollView, context: Context) {
        guard let view = scroll.documentView as? NSTextView, view.string != text else { return }
        view.string = text
        view.textStorage?.setAttributes([.foregroundColor: NSColor.textColor,
                                         .font: NSFont.monospacedSystemFont(ofSize: 12, weight: .regular)],
                                        range: NSRange(location: 0, length: (text as NSString).length))
        guard highlightsDiff else { return }
        (text as NSString).enumerateSubstrings(in: NSRange(location: 0, length: (text as NSString).length),
                                              options: .byLines) { line, range, _, _ in
            let color: NSColor?
            if line?.hasPrefix("+") == true { color = .systemGreen }
            else if line?.hasPrefix("-") == true { color = .systemRed }
            else if line?.hasPrefix("@@") == true { color = .systemBlue }
            else { color = nil }
            if let color {
                view.textStorage?.addAttribute(.backgroundColor, value: color.withAlphaComponent(0.12), range: range)
            }
        }
    }
}
