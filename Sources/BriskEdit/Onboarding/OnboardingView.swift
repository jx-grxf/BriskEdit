import SwiftUI

/// First-run onboarding: a short, focused flow that configures the essentials
/// (performance, editor, source control). Presented as a compact sheet; the main
/// window expands to full size once it's dismissed. Re-triggerable from
/// Settings ▸ General.
struct OnboardingView: View {
    @Bindable var preferences: Preferences
    var onFinish: () -> Void
    /// Opens a folder picker — wired so the final step can drop the user straight
    /// into a project instead of an empty window.
    var onOpenFolder: () -> Void = {}

    @State private var step = 0
    @State private var tools: [ToolHealthItem] = []
    @State private var toolsScanned = false
    @State private var installStates: [String: ToolInstallState] = [:]
    @State private var cliState: CLIState = CLIInstaller.isInstalled ? .installed : .idle
    @Environment(ThemeStore.self) private var themeStore

    private let steps: [OnboardingStep] = [.welcome, .tools, .performance, .editor, .git, .finish]
    private var current: OnboardingStep { steps[step] }
    private var isLast: Bool { step == steps.count - 1 }

    private enum CLIState: Equatable {
        case idle, installing, installed, failed(String)
    }

    var body: some View {
        VStack(spacing: 0) {
            topBar
            Divider().overlay(.white.opacity(0.06))
            content
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .id(step)
                .transition(.asymmetric(
                    insertion: .move(edge: .trailing).combined(with: .opacity),
                    removal: .move(edge: .leading).combined(with: .opacity)
                ))
            Divider().overlay(.white.opacity(0.06))
            footer
        }
        .frame(width: 560, height: 560)
        .background(BackdropGradient())
        .preferredColorScheme(.dark)
        .tint(accent)
    }

    private let accent = Color(red: 0.46, green: 0.52, blue: 0.96)

    // MARK: Bars

    private var topBar: some View {
        HStack(spacing: 8) {
            Image(systemName: "bolt.horizontal.fill")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(accent)
            Text("BriskEdit")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.white.opacity(0.85))
            Spacer()
            if !isLast {
                Button("Skip") { finish() }
                    .buttonStyle(.plain)
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(0.45))
            }
        }
        .padding(.horizontal, 22)
        .padding(.vertical, 14)
    }

    private var footer: some View {
        HStack {
            Button { advance(by: -1) } label: {
                Label("Back", systemImage: "chevron.left").labelStyle(.titleAndIcon)
            }
            .buttonStyle(.plain)
            .font(.subheadline)
            .foregroundStyle(.white.opacity(0.6))
            .opacity(step == 0 ? 0 : 1)
            .disabled(step == 0)

            Spacer()
            ProgressDots(count: steps.count, current: step, accent: accent)
            Spacer()

            Button { isLast ? finish() : advance(by: 1) } label: {
                Text(isLast ? "Get Started" : "Continue")
                    .font(.subheadline.weight(.semibold))
                    .frame(minWidth: 92)
                    .padding(.vertical, 7)
                    .padding(.horizontal, 14)
                    .background(Capsule().fill(accent))
                    .foregroundStyle(.white)
            }
            .buttonStyle(.plain)
            .keyboardShortcut(.defaultAction)
        }
        .padding(.horizontal, 22)
        .padding(.vertical, 14)
    }

    // MARK: Content

    @ViewBuilder
    private var content: some View {
        ScrollView {
            VStack(spacing: 20) {
                switch current {
                case .welcome: welcomeStep
                case .tools: toolsStep
                case .performance: performanceStep
                case .editor: editorStep
                case .git: gitStep
                case .finish: finishStep
                }
            }
            .padding(.horizontal, 28)
            .padding(.vertical, 26)
            .frame(maxWidth: .infinity)
        }
    }

    private var welcomeStep: some View {
        OnboardingHeader(
            symbol: "bolt.horizontal.fill",
            title: "Welcome to BriskEdit",
            subtitle: "A native macOS editor that opens instantly and uses the toolchains, language servers and formatters already on your Mac.",
            accent: accent
        )
    }

    private var toolsStep: some View {
        let available = tools.filter(\.isAvailable)
        let groups = missingGroups
        return VStack(spacing: 18) {
            OnboardingHeader(
                symbol: "wrench.and.screwdriver.fill",
                title: toolsScanned ? "Ready to use your tools" : "Scanning your Mac…",
                subtitle: toolsScanned
                    ? "BriskEdit found \(available.count) developer tool\(available.count == 1 ? "" : "s") already installed. Install anything that's missing right here — or skip and add it later."
                    : "Looking for the compilers, language servers and formatters already on your Mac.",
                accent: accent
            )
            GlassCard {
                if !toolsScanned {
                    HStack(spacing: 10) {
                        ProgressView().controlSize(.small).tint(.white)
                        Text("Probing your PATH…").foregroundStyle(.white.opacity(0.6)).font(.subheadline)
                    }
                    .frame(maxWidth: .infinity, minHeight: 96)
                } else if available.isEmpty && groups.isEmpty {
                    VStack(spacing: 6) {
                        Text("Couldn't probe your tools")
                            .font(.subheadline.weight(.semibold)).foregroundStyle(.white)
                        Text("That's fine — install toolchains any time and BriskEdit picks them up automatically.")
                            .font(.caption).foregroundStyle(.white.opacity(0.55))
                            .multilineTextAlignment(.center)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .frame(maxWidth: .infinity, minHeight: 96)
                } else {
                    VStack(alignment: .leading, spacing: 14) {
                        if !available.isEmpty {
                            ToolChipFlow(items: available, accent: accent)
                        }
                        if !groups.isEmpty {
                            if !available.isEmpty { Divider().overlay(.white.opacity(0.08)) }
                            Text("Install more (optional)")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.white.opacity(0.55))
                            ForEach(groups) { group in
                                MissingToolInstallRow(
                                    group: group,
                                    accent: accent,
                                    state: installStates[group.id] ?? .idle,
                                    onInstall: { install(group) }
                                )
                            }
                        }
                    }
                }
            }
        }
        .task {
            guard !toolsScanned else { return }
            tools = await ToolHealthService.snapshot()
            withAnimation(.easeOut(duration: 0.25)) { toolsScanned = true }
        }
    }

    /// Missing tools collapsed by their install action, so the five things that
    /// `xcode-select --install` provides show as one "Xcode Command Line Tools"
    /// row instead of five.
    private var missingGroups: [InstallableGroup] {
        let missing = tools.filter { !$0.isAvailable && $0.descriptor.installCommand != nil }
        let grouped = Dictionary(grouping: missing) { $0.descriptor.installCommand ?? "" }
        return grouped.compactMap { command, items -> InstallableGroup? in
            guard let first = items.first else { return nil }
            return InstallableGroup(
                id: command,
                command: command,
                hint: first.descriptor.installHint,
                toolNames: items.map(\.descriptor.name),
                descriptor: first.descriptor
            )
        }
        .sorted { $0.toolNames.count > $1.toolNames.count }
    }

    private func install(_ group: InstallableGroup) {
        installStates[group.id] = .installing
        Task {
            let result = await ToolHealthService.install(group.descriptor)
            if result.ok {
                installStates[group.id] = .done
                // Re-probe so freshly installed tools move into the "found" set.
                tools = await ToolHealthService.snapshot()
            } else {
                installStates[group.id] = .failed
            }
        }
    }

    private var performanceStep: some View {
        VStack(spacing: 18) {
            OnboardingHeader(
                symbol: "speedometer",
                title: "Pick your pace",
                subtitle: "Run flat-out or ease off to save battery. Change it any time in Settings.",
                accent: accent
            )
            VStack(spacing: 8) {
                ForEach(Preferences.PerformanceMode.allCases) { mode in
                    OnboardingChoiceRow(
                        symbol: mode.systemImage,
                        title: mode.title,
                        detail: mode.explanation,
                        isSelected: preferences.performanceMode == mode,
                        accent: accent
                    ) {
                        withAnimation(.snappy) { preferences.performanceMode = mode }
                    }
                }
            }
        }
    }

    private var editorStep: some View {
        VStack(spacing: 18) {
            OnboardingHeader(
                symbol: "text.cursor",
                title: "Make it yours",
                subtitle: "A theme and a couple of basics — everything else lives in Settings.",
                accent: accent
            )
            GlassCard {
                VStack(spacing: 14) {
                    HStack {
                        Text("Theme").foregroundStyle(.white.opacity(0.8))
                        Spacer()
                        Picker("", selection: $preferences.themeID) {
                            ForEach(themeStore.themes) { theme in
                                Text(theme.name).tag(theme.id)
                            }
                        }
                        .labelsHidden()
                        .frame(maxWidth: 190)
                    }
                    Divider().overlay(.white.opacity(0.08))
                    Stepper(value: $preferences.fontSize, in: 9...28, step: 1) {
                        HStack {
                            Text("Font size").foregroundStyle(.white.opacity(0.8))
                            Spacer()
                            Text("\(Int(preferences.fontSize)) pt").foregroundStyle(.white.opacity(0.55))
                        }
                    }
                    Divider().overlay(.white.opacity(0.08))
                    Toggle(isOn: $preferences.formatOnSave) {
                        Text("Format on save").foregroundStyle(.white.opacity(0.8))
                    }
                    .toggleStyle(.switch)
                }
            }
            if let theme = themeStore.theme(id: preferences.themeID) {
                ThemePreview(theme: theme)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private var gitStep: some View {
        VStack(spacing: 18) {
            OnboardingHeader(
                symbol: "arrow.triangle.branch",
                title: "Source control",
                subtitle: "BriskEdit reads your repo directly. Don't use Git? Turn it off and keep the chrome clean.",
                accent: accent
            )
            GlassCard {
                VStack(spacing: 14) {
                    Toggle(isOn: $preferences.sourceControlEnabled) {
                        OnboardingToggleLabel(title: "Use source control", detail: "Source Control sidebar, gutter diffs and inline blame.")
                    }
                    .toggleStyle(.switch)
                    Divider().overlay(.white.opacity(0.08))
                    Toggle(isOn: $preferences.showGitGutter) {
                        OnboardingToggleLabel(title: "Git gutter", detail: "Mark added and changed lines in the gutter.")
                    }
                    .toggleStyle(.switch)
                    .disabled(!preferences.sourceControlEnabled)
                    Divider().overlay(.white.opacity(0.08))
                    Toggle(isOn: $preferences.showInlineGitBlame) {
                        OnboardingToggleLabel(title: "Inline blame", detail: "Show who last changed the current line.")
                    }
                    .toggleStyle(.switch)
                    .disabled(!preferences.sourceControlEnabled)
                }
            }
        }
    }

    private var finishStep: some View {
        VStack(spacing: 18) {
            OnboardingHeader(
                symbol: "checkmark.seal.fill",
                title: "You're all set",
                subtitle: "Add the command-line launcher, then open a folder. Replay this any time from Settings ▸ General.",
                accent: accent
            )
            GlassCard {
                VStack(spacing: 14) {
                    cliRow
                    Divider().overlay(.white.opacity(0.08))
                    Button(action: openFolderAndFinish) {
                        HStack(spacing: 12) {
                            Image(systemName: "folder.fill.badge.plus")
                                .foregroundStyle(accent)
                                .frame(width: 22)
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Open a folder").foregroundStyle(.white.opacity(0.88))
                                Text("Jump straight into a project.")
                                    .font(.caption2).foregroundStyle(.white.opacity(0.5))
                            }
                            Spacer(minLength: 8)
                            Image(systemName: "chevron.right")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.white.opacity(0.4))
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private var cliRow: some View {
        HStack(spacing: 12) {
            Image(systemName: "terminal.fill")
                .foregroundStyle(accent)
                .frame(width: 22)
            VStack(alignment: .leading, spacing: 2) {
                Text("Command-line launcher").foregroundStyle(.white.opacity(0.88))
                Text(cliSubtitle)
                    .font(.caption2).foregroundStyle(.white.opacity(0.5))
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 8)
            cliControl
        }
    }

    @ViewBuilder
    private var cliControl: some View {
        switch cliState {
        case .installing:
            ProgressView().controlSize(.small).tint(.white)
        case .installed:
            HStack(spacing: 4) {
                Image(systemName: "checkmark.circle.fill")
                Text("Installed")
            }
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(accent)
        case .idle, .failed:
            Button("Install") { installCLI() }
                .buttonStyle(.plain)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(accent)
        }
    }

    private var cliSubtitle: String {
        switch cliState {
        case .installed:
            let names = CLIInstaller.installedCommandNames
            return names.isEmpty
                ? "Installed."
                : "Open files from any terminal with “\(names.joined(separator: "” or “"))”."
        case .failed(let message):
            return message
        case .idle, .installing:
            return "Open files and folders with “\(CLIInstaller.primaryCommandName)” from any terminal."
        }
    }

    // MARK: Actions

    private func advance(by delta: Int) {
        let next = max(0, min(steps.count - 1, step + delta))
        withAnimation(.spring(response: 0.4, dampingFraction: 0.85)) { step = next }
    }

    private func installCLI() {
        cliState = .installing
        Task {
            do {
                try await CLIInstaller.install()
                cliState = .installed
            } catch {
                cliState = .failed(error.localizedDescription)
            }
        }
    }

    private func openFolderAndFinish() {
        finish()
        onOpenFolder()
    }

    private func finish() {
        preferences.hasCompletedOnboarding = true
        onFinish()
    }
}

/// A wrapping grid of detected-tool chips, each with a checkmark.
private struct ToolChipFlow: View {
    let items: [ToolHealthItem]
    let accent: Color

    private let columns = [GridItem(.adaptive(minimum: 116, maximum: 200), spacing: 8)]

    var body: some View {
        LazyVGrid(columns: columns, alignment: .leading, spacing: 8) {
            ForEach(items) { item in
                HStack(spacing: 6) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.caption2)
                        .foregroundStyle(accent)
                    Text(item.descriptor.name)
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.85))
                        .lineLimit(1)
                        .truncationMode(.tail)
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 6)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(.white.opacity(0.05))
                )
            }
        }
    }
}

private enum OnboardingStep {
    case welcome, tools, performance, editor, git, finish
}

enum ToolInstallState: Equatable {
    case idle, installing, done, failed
}

/// A set of missing tools that share one install action (e.g. everything
/// `xcode-select --install` provides), shown as a single installable row.
struct InstallableGroup: Identifiable {
    let id: String
    let command: String
    let hint: String
    let toolNames: [String]
    let descriptor: ToolDescriptor
}

/// One missing-tool row in onboarding: what it enables, the install command, and
/// an Install button that reflects progress/result.
private struct MissingToolInstallRow: View {
    let group: InstallableGroup
    let accent: Color
    let state: ToolInstallState
    let onInstall: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(group.toolNames.joined(separator: ", "))
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.white.opacity(0.88))
                    .lineLimit(1)
                    .truncationMode(.tail)
                Text(group.hint)
                    .font(.caption2)
                    .foregroundStyle(.white.opacity(0.5))
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
            Spacer(minLength: 8)
            control
        }
        .padding(.vertical, 2)
    }

    @ViewBuilder
    private var control: some View {
        switch state {
        case .installing:
            ProgressView().controlSize(.small).tint(.white)
        case .done:
            HStack(spacing: 4) {
                Image(systemName: "checkmark.circle.fill")
                Text("Installed")
            }
            .font(.caption.weight(.semibold))
            .foregroundStyle(accent)
        case .failed:
            Button("Retry") { onInstall() }
                .buttonStyle(.plain)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.orange)
        case .idle:
            Button("Install") { onInstall() }
                .buttonStyle(.plain)
                .font(.caption.weight(.semibold))
                .foregroundStyle(accent)
        }
    }
}

// MARK: - Pieces

private struct OnboardingHeader: View {
    let symbol: String
    let title: String
    let subtitle: String
    let accent: Color
    @State private var appeared = false

    var body: some View {
        VStack(spacing: 12) {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(accent.opacity(0.16))
                .frame(width: 52, height: 52)
                .overlay(
                    Image(systemName: symbol)
                        .font(.system(size: 24, weight: .semibold))
                        .foregroundStyle(accent)
                )
                .scaleEffect(appeared ? 1 : 0.85)
                .opacity(appeared ? 1 : 0)
            Text(title)
                .font(.system(size: 22, weight: .bold))
                .foregroundStyle(.white)
                .multilineTextAlignment(.center)
            Text(subtitle)
                .font(.subheadline)
                .foregroundStyle(.white.opacity(0.62))
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: 440)
        }
        .opacity(appeared ? 1 : 0)
        .onAppear {
            withAnimation(.spring(response: 0.5, dampingFraction: 0.8)) { appeared = true }
        }
    }
}

private struct OnboardingChoiceRow: View {
    let symbol: String
    let title: String
    let detail: String
    let isSelected: Bool
    let accent: Color
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: symbol)
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(isSelected ? AnyShapeStyle(accent) : AnyShapeStyle(.white.opacity(0.5)))
                    .frame(width: 24)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.subheadline.weight(.semibold)).foregroundStyle(.white)
                    Text(detail).font(.caption2).foregroundStyle(.white.opacity(0.55))
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 8)
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(isSelected ? AnyShapeStyle(accent) : AnyShapeStyle(.white.opacity(0.25)))
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 11, style: .continuous)
                    .fill(.white.opacity(isSelected ? 0.10 : 0.04))
                    .overlay(
                        RoundedRectangle(cornerRadius: 11, style: .continuous)
                            .strokeBorder(isSelected ? AnyShapeStyle(accent.opacity(0.7)) : AnyShapeStyle(.white.opacity(0.07)))
                    )
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

private struct OnboardingToggleLabel: View {
    let title: String
    let detail: String
    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).foregroundStyle(.white.opacity(0.88))
            Text(detail).font(.caption2).foregroundStyle(.white.opacity(0.5))
        }
    }
}

private struct GlassCard<Content: View>: View {
    @ViewBuilder var content: Content
    var body: some View {
        content
            .padding(16)
            .frame(maxWidth: .infinity)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(.white.opacity(0.05))
                    .overlay(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .strokeBorder(.white.opacity(0.08))
                    )
            )
    }
}

private struct ProgressDots: View {
    let count: Int
    let current: Int
    let accent: Color
    var body: some View {
        HStack(spacing: 6) {
            ForEach(0..<count, id: \.self) { i in
                Capsule()
                    .fill(i == current ? AnyShapeStyle(accent) : AnyShapeStyle(.white.opacity(0.22)))
                    .frame(width: i == current ? 18 : 6, height: 6)
                    .animation(.spring(response: 0.35, dampingFraction: 0.8), value: current)
            }
        }
    }
}

/// A calm, dark blue→violet backdrop with one faint top highlight. No animation —
/// restrained on purpose.
private struct BackdropGradient: View {
    var body: some View {
        LinearGradient(
            colors: [
                Color(red: 0.05, green: 0.06, blue: 0.13),
                Color(red: 0.08, green: 0.07, blue: 0.17),
                Color(red: 0.10, green: 0.07, blue: 0.20),
            ],
            startPoint: .top,
            endPoint: .bottom
        )
        .overlay(alignment: .top) {
            RadialGradient(
                colors: [Color(red: 0.30, green: 0.34, blue: 0.72).opacity(0.35), .clear],
                center: .top,
                startRadius: 0,
                endRadius: 360
            )
        }
        .ignoresSafeArea()
    }
}
