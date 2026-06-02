import SwiftUI

struct ToolHealthPanel: View {
    @Environment(\.dismiss) private var dismiss
    @State private var items: [ToolHealthItem] = []
    @State private var isLoading = true
    @State private var feedback: String?
    /// Tool names whose install is currently running, so each row can show its
    /// own progress bar (instead of one overlay covering the whole list).
    @State private var installing: Set<String> = []

    var body: some View {
        VStack(spacing: 0) {
            header
            if let feedback {
                Text(feedback)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
                    .lineLimit(3)
                    .padding(.horizontal, 14)
                    .padding(.bottom, 8)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            Divider()
            List {
                ForEach(ToolCategory.allCases, id: \.self) { category in
                    Section(category.rawValue) {
                        ForEach(items.filter { $0.descriptor.category == category }) { item in
                            ToolHealthRow(item: item, isInstalling: installing.contains(item.descriptor.name)) { descriptor in
                                Task { await install(descriptor) }
                            }
                        }
                    }
                }
            }
            .overlay {
                if isLoading {
                    ProgressView()
                        .controlSize(.large)
                }
            }
        }
        .frame(width: 720, height: 520)
        .task { await refresh() }
    }

    private var header: some View {
        HStack(spacing: 12) {
            Image(systemName: "stethoscope")
                .font(.title2)
                .foregroundStyle(.tint)
            VStack(alignment: .leading, spacing: 2) {
                Text("Tool Health")
                    .font(.headline)
                Text(summary)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button("Refresh", systemImage: "arrow.clockwise") {
                Task { await refresh() }
            }
            .disabled(isLoading)
            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark")
            }
            .buttonStyle(.borderless)
            .keyboardShortcut(.cancelAction)
            .help("Close")
            .accessibilityLabel("Close")
        }
        .padding(14)
    }

    private var summary: String {
        guard !items.isEmpty else { return "Checking local developer tools..." }
        let available = items.filter(\.isAvailable).count
        return "\(available) of \(items.count) tools available on this Mac"
    }

    @MainActor
    private func refresh() async {
        isLoading = true
        items = await ToolHealthService.snapshot()
        isLoading = false
    }

    @MainActor
    private func install(_ descriptor: ToolDescriptor) async {
        installing.insert(descriptor.name)
        feedback = "Installing \(descriptor.name)…"
        let result = await ToolHealthService.install(descriptor)
        feedback = result.ok ? "\(descriptor.name): install finished." : "\(descriptor.name): \(result.output)"
        items = await ToolHealthService.snapshot()
        installing.remove(descriptor.name)
    }
}

private struct ToolHealthRow: View {
    let item: ToolHealthItem
    var isInstalling: Bool = false
    let onInstall: (ToolDescriptor) -> Void

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: item.isAvailable ? "checkmark.circle.fill" : "minus.circle")
                .foregroundStyle(item.isAvailable ? .green : .secondary)
                .frame(width: 18)
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 8) {
                    Text(item.descriptor.name)
                        .font(.body.weight(.medium))
                    Text(item.descriptor.usedFor)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Text(item.path ?? item.descriptor.installHint)
                    .font(.caption.monospaced())
                    .foregroundStyle(item.isAvailable ? Color.secondary : Color.orange)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            Spacer()
            if isInstalling {
                ProgressView()
                    .progressViewStyle(.linear)
                    .tint(.green)
                    .frame(width: 120)
            } else if !item.isAvailable, item.descriptor.installCommand != nil {
                Button("Install") { onInstall(item.descriptor) }
                    .controlSize(.small)
            }
        }
        .padding(.vertical, 4)
    }
}
