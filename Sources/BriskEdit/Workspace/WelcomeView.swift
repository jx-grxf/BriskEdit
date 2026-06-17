import SwiftUI

/// Shown in the editor area when no file is open: a two-pane welcome with quick
/// actions on the left and recently opened folders on the right. Replaces the
/// bare "Open a file" placeholder so a fresh launch feels intentional.
struct WelcomeView: View {
    let recents: [URL]
    let onNewFile: () -> Void
    let onOpenFile: () -> Void
    let onOpenFolder: () -> Void
    let onOpenRecent: (URL) -> Void

    private var appName: String { "BriskEdit" }

    private var versionLabel: String {
        let info = Bundle.main.infoDictionary
        let short = info?["CFBundleShortVersionString"] as? String ?? "1.0"
        return "Version \(short)"
    }

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            actionsPane
                .frame(maxWidth: .infinity, alignment: .leading)
            if !recents.isEmpty {
                Divider()
                recentsPane
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .frame(maxWidth: 720, maxHeight: 460)
        .padding(40)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var actionsPane: some View {
        VStack(alignment: .leading, spacing: 0) {
            Image(systemName: "bolt.horizontal.fill")
                .font(.system(size: 44, weight: .semibold))
                .foregroundStyle(.tint)
                .padding(.bottom, 18)
            Text(appName)
                .font(.system(size: 34, weight: .bold))
            Text("Johannes Grof · MIT")
                .font(.callout)
                .foregroundStyle(.secondary)
            Text(versionLabel)
                .font(.caption)
                .foregroundStyle(.tertiary)
                .padding(.bottom, 26)

            VStack(alignment: .leading, spacing: 10) {
                WelcomeAction(title: "New File", subtitle: "Start an untitled buffer", symbol: "doc.badge.plus", shortcut: "⌘N", action: onNewFile)
                WelcomeAction(title: "Open File…", subtitle: "Edit an existing file", symbol: "doc.text", action: onOpenFile)
                WelcomeAction(title: "Open Folder…", subtitle: "Browse a project", symbol: "folder", action: onOpenFolder)
            }
            Spacer(minLength: 0)
        }
        .padding(.trailing, 28)
    }

    private var recentsPane: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Recent")
                .font(.headline)
                .foregroundStyle(.secondary)
            ScrollView {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(recents, id: \.self) { url in
                        WelcomeRecentRow(url: url) { onOpenRecent(url) }
                    }
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.leading, 28)
    }
}

private struct WelcomeAction: View {
    let title: String
    let subtitle: String
    let symbol: String
    var shortcut: String? = nil
    let action: () -> Void
    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: symbol)
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(.tint)
                    .frame(width: 24)
                VStack(alignment: .leading, spacing: 1) {
                    Text(title).font(.body.weight(.medium))
                    Text(subtitle).font(.caption).foregroundStyle(.secondary)
                }
                Spacer(minLength: 8)
                if let shortcut {
                    Text(shortcut)
                        .font(.caption.monospaced())
                        .foregroundStyle(.tertiary)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 9)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color.primary.opacity(isHovering ? 0.06 : 0))
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
    }
}

private struct WelcomeRecentRow: View {
    let url: URL
    let action: () -> Void
    @State private var isHovering = false

    private var exists: Bool { FileManager.default.fileExists(atPath: url.path) }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: "folder.fill")
                    .foregroundStyle(exists ? AnyShapeStyle(.tint) : AnyShapeStyle(.secondary))
                VStack(alignment: .leading, spacing: 1) {
                    Text(url.lastPathComponent)
                        .font(.body.weight(.medium))
                        .foregroundStyle(exists ? .primary : .secondary)
                        .lineLimit(1)
                    Text(url.deletingLastPathComponent().path)
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                        .truncationMode(.head)
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(Color.primary.opacity(isHovering ? 0.06 : 0))
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!exists)
        .onHover { isHovering = $0 }
        .help(url.path)
    }
}
