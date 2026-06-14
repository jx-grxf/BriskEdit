import SwiftUI

/// First-run onboarding: a short, focused flow that configures the essentials
/// (performance, editor, source control). Presented as a compact sheet; the main
/// window expands to full size once it's dismissed. Re-triggerable from
/// Settings ▸ General.
struct OnboardingView: View {
    @Bindable var preferences: Preferences
    var onFinish: () -> Void

    @State private var step = 0
    @Environment(ThemeStore.self) private var themeStore

    private let steps: [OnboardingStep] = [.welcome, .performance, .editor, .git, .finish]
    private var current: OnboardingStep { steps[step] }
    private var isLast: Bool { step == steps.count - 1 }

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
        }
    }

    private var gitStep: some View {
        VStack(spacing: 18) {
            OnboardingHeader(
                symbol: "arrow.triangle.branch",
                title: "Source control, built in",
                subtitle: "BriskEdit reads your repo directly — gutter diffs and inline blame.",
                accent: accent
            )
            GlassCard {
                VStack(spacing: 14) {
                    Toggle(isOn: $preferences.showGitGutter) {
                        OnboardingToggleLabel(title: "Git gutter", detail: "Mark added and changed lines in the gutter.")
                    }
                    .toggleStyle(.switch)
                    Divider().overlay(.white.opacity(0.08))
                    Toggle(isOn: $preferences.showInlineGitBlame) {
                        OnboardingToggleLabel(title: "Inline blame", detail: "Show who last changed the current line.")
                    }
                    .toggleStyle(.switch)
                }
            }
        }
    }

    private var finishStep: some View {
        OnboardingHeader(
            symbol: "checkmark.seal.fill",
            title: "You're all set",
            subtitle: "Open a folder to get going. Replay this any time from Settings ▸ General.",
            accent: accent
        )
    }

    // MARK: Actions

    private func advance(by delta: Int) {
        let next = max(0, min(steps.count - 1, step + delta))
        withAnimation(.spring(response: 0.4, dampingFraction: 0.85)) { step = next }
    }

    private func finish() {
        preferences.hasCompletedOnboarding = true
        onFinish()
    }
}

private enum OnboardingStep {
    case welcome, performance, editor, git, finish
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
