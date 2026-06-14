import SwiftUI

/// The "What's New in BriskEdit" page, shown as a tab after an update. A clean,
/// scrollable layout: a header with the version, then grouped highlight rows.
struct WhatsNewView: View {
    let version: String

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                header
                ForEach(WhatsNew.sections) { section in
                    VStack(alignment: .leading, spacing: 12) {
                        Text(section.name.uppercased())
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                            .tracking(0.6)
                        VStack(spacing: 0) {
                            ForEach(Array(section.highlights.enumerated()), id: \.element.id) { index, highlight in
                                HighlightRow(highlight: highlight)
                                if index < section.highlights.count - 1 {
                                    Divider().padding(.leading, 56)
                                }
                            }
                        }
                        .background(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .fill(Color.primary.opacity(0.035))
                        )
                    }
                }
            }
            .frame(maxWidth: 720, alignment: .leading)
            .padding(.horizontal, 40)
            .padding(.vertical, 44)
            .frame(maxWidth: .infinity, alignment: .center)
        }
        .background(.background)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            Image(systemName: "bolt.horizontal.fill")
                .font(.system(size: 40, weight: .semibold))
                .foregroundStyle(.tint)
                .padding(.bottom, 6)
            Text("What's New in BriskEdit")
                .font(.system(size: 30, weight: .bold))
            Text("Version \(version)")
                .font(.title3)
                .foregroundStyle(.secondary)
            Text(WhatsNew.tagline)
                .font(.body)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 4)
        }
    }
}

private struct HighlightRow: View {
    let highlight: WhatsNew.Highlight

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: highlight.symbol)
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(highlight.tint)
                .frame(width: 28, height: 28)
                .padding(.top, 2)
            VStack(alignment: .leading, spacing: 3) {
                Text(highlight.title)
                    .font(.headline)
                Text(highlight.detail)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
    }
}
