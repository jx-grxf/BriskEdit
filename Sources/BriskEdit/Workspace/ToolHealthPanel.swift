import SwiftUI

struct ToolHealthPanel: View {
    @State private var items: [ToolHealthItem] = []
    @State private var isLoading = true

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            List {
                ForEach(ToolCategory.allCases, id: \.self) { category in
                    Section(category.rawValue) {
                        ForEach(items.filter { $0.descriptor.category == category }) { item in
                            ToolHealthRow(item: item)
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
}

private struct ToolHealthRow: View {
    let item: ToolHealthItem

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
        }
        .padding(.vertical, 4)
    }
}
