import AppKit
import SwiftUI

/// Shown in the editor area when no file is open: what you can do on the left,
/// where you left off on the right.
///
/// The branding is the app's own icon and accent colour, so a nightly identifies
/// itself without a second design. Everything on screen is information the user
/// can act on — no decorative copy, no filler subtitles.
struct WelcomeView: View {
    let recents: [URL]
    /// When each folder was last opened, for the relative line under its name.
    var openedAt: (URL) -> Date? = { _ in nil }
    let onNewFile: () -> Void
    let onOpenFile: () -> Void
    let onOpenFolder: () -> Void
    let onOpenRecent: (URL) -> Void

    @Environment(Preferences.self) private var preferences
    @Environment(\.accessibilityReduceMotion) private var accessibilityReduceMotion
    @State private var branches: [URL: String] = [:]
    @State private var hasAppeared = false

    /// Enough to recognize the project you want, few enough to stay scannable.
    private static let maximumRecents = 6

    private var shownRecents: [URL] { Array(recents.prefix(Self.maximumRecents)) }
    private var reducesMotion: Bool { preferences.reduceMotion || accessibilityReduceMotion }
    private var appName: String { AppDistribution.current.displayName }
    private var version: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
    }

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            actionsPane
                .frame(maxWidth: .infinity, alignment: .leading)
            if !shownRecents.isEmpty {
                Divider()
                recentsPane
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .frame(maxWidth: 760, maxHeight: 460)
        .padding(40)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .task(id: shownRecents) {
            branches = await GitHeadProbe.branches(for: shownRecents)
        }
        .onAppear { hasAppeared = true }
    }

    private var actionsPane: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
                .welcomeEntrance(step: 0, isVisible: hasAppeared, reducesMotion: reducesMotion)
            VStack(alignment: .leading, spacing: 2) {
                WelcomeAction(title: "Open Folder…", symbol: "folder", shortcut: "⇧⌘O", action: onOpenFolder)
                WelcomeAction(title: "Open File…", symbol: "doc", shortcut: "⌘O", action: onOpenFile)
                WelcomeAction(title: "New File", symbol: "square.and.pencil", shortcut: "⌘N", action: onNewFile)
            }
            .padding(.top, 26)
            .welcomeEntrance(step: 1, isVisible: hasAppeared, reducesMotion: reducesMotion)
            Spacer(minLength: 0)
        }
        .padding(.trailing, 28)
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 14) {
            Image(nsImage: NSApplication.shared.applicationIconImage)
                .resizable()
                .interpolation(.high)
                .frame(width: 60, height: 60)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 4) {
                Text(appName)
                    .font(.system(size: 26, weight: .semibold))
                buildLine
            }
            .padding(.top, 3)
        }
    }

    /// Version, plus the commit for a nightly — the two things worth knowing
    /// before reporting that a build broke.
    private var buildLine: some View {
        HStack(spacing: 6) {
            Text(version)
                .font(.caption.monospaced())
                .foregroundStyle(.secondary)
            if let commit = AppDistribution.sourceCommit,
               let url = URL(string: "\(AppDistribution.repositoryURL)/commit/\(commit)") {
                Text(verbatim: "·")
                    .font(.caption)
                    .foregroundStyle(.quaternary)
                Link(destination: url) {
                    Text("dev @ \(commit)")
                        .font(.caption.monospaced())
                }
                .help("Open this commit on GitHub")
            }
        }
    }

    private var recentsPane: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Recent")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)
                .welcomeEntrance(step: 1, isVisible: hasAppeared, reducesMotion: reducesMotion)
            VStack(alignment: .leading, spacing: 2) {
                ForEach(Array(shownRecents.enumerated()), id: \.element) { index, url in
                    WelcomeRecentRow(
                        url: url,
                        branch: branches[url],
                        openedAt: openedAt(url),
                        action: { onOpenRecent(url) }
                    )
                    // The rows share the last two steps: a six-item stagger would
                    // turn a 200 ms entrance into something you wait for.
                    .welcomeEntrance(step: index < 3 ? 2 : 3, isVisible: hasAppeared, reducesMotion: reducesMotion)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.leading, 28)
    }
}

/// One short entrance for the whole screen: fade plus a 6 pt rise, in four
/// steps 30 ms apart. Long enough to feel deliberate, short enough that it never
/// stands between the user and the first click — and gone entirely when the
/// system or the performance profile asks for less motion.
private struct WelcomeEntrance: ViewModifier {
    let step: Int
    let isVisible: Bool
    let reducesMotion: Bool

    func body(content: Content) -> some View {
        content
            .opacity(isVisible || reducesMotion ? 1 : 0)
            .offset(y: isVisible || reducesMotion ? 0 : 6)
            .animation(
                reducesMotion ? nil : .smooth(duration: 0.22).delay(Double(step) * 0.03),
                value: isVisible
            )
    }
}

private extension View {
    func welcomeEntrance(step: Int, isVisible: Bool, reducesMotion: Bool) -> some View {
        modifier(WelcomeEntrance(step: step, isVisible: isVisible, reducesMotion: reducesMotion))
    }
}

private struct WelcomeAction: View {
    let title: String
    let symbol: String
    let shortcut: String
    let action: () -> Void
    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: symbol)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(isHovering ? AnyShapeStyle(.tint) : AnyShapeStyle(.secondary))
                    .frame(width: 20)
                Text(title)
                    .font(.body)
                Spacer(minLength: 16)
                Text(shortcut)
                    .font(.caption.monospaced())
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(Color.primary.opacity(isHovering ? 0.05 : 0))
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
    }
}

private struct WelcomeRecentRow: View {
    let url: URL
    let branch: String?
    let openedAt: Date?
    let action: () -> Void
    @State private var isHovering = false

    private var exists: Bool { FileManager.default.fileExists(atPath: url.path) }

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 1) {
                Text(url.lastPathComponent)
                    .font(.body)
                    .foregroundStyle(exists ? .primary : .secondary)
                    .lineLimit(1)
                detail
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(Color.primary.opacity(isHovering ? 0.05 : 0))
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!exists)
        .onHover { isHovering = $0 }
        .help(url.path)
    }

    /// Branch and last visit when we know them, the parent path otherwise — a
    /// row never falls back to empty space.
    @ViewBuilder
    private var detail: some View {
        if !exists {
            Text("Missing")
        } else if branch != nil || openedAt != nil {
            HStack(spacing: 6) {
                if let branch {
                    Label(branch, systemImage: "arrow.triangle.branch")
                        .labelStyle(.titleAndIcon)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                if let openedAt {
                    if branch != nil {
                        Text(verbatim: "·").foregroundStyle(.quaternary)
                    }
                    Text(openedAt, format: .relative(presentation: .named))
                }
            }
        } else {
            Text(url.deletingLastPathComponent().path)
                .truncationMode(.head)
        }
    }
}
