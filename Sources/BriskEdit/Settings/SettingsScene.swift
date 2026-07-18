import AppKit
import SwiftUI

struct SettingsScene: View {
    @Environment(Preferences.self) private var preferences
    @Environment(\.accessibilityReduceMotion) private var accessibilityReduceMotion

    var body: some View {
        TabView {
            GeneralPreferencesView()
                .tabItem { Label("General", systemImage: "gearshape") }
            AppearancePreferencesView()
                .tabItem { Label("Appearance", systemImage: "paintpalette") }
            EditorPreferencesView()
                .tabItem { Label("Editor", systemImage: "text.cursor") }
            PerformancePreferencesView()
                .tabItem { Label("Performance", systemImage: "speedometer") }
            TerminalPreferencesView()
                .tabItem { Label("Terminal", systemImage: "terminal") }
            UpdatePreferencesView()
                .tabItem { Label("Updates", systemImage: "arrow.triangle.2.circlepath") }
            ExperimentalPreferencesView()
                .tabItem { Label("Experimental", systemImage: "flask") }
            AboutPreferencesView()
                .tabItem { Label("About", systemImage: "info.circle") }
        }
        // Wide enough that all tab items fit on one row; otherwise macOS collapses
        // the overflow into a \"»\" popover whose items don't reliably click.
        .frame(width: 720, height: 480)
        .transaction { transaction in
            if preferences.reduceMotion || accessibilityReduceMotion { transaction.disablesAnimations = true }
        }
    }
}

// MARK: - General

private struct GeneralPreferencesView: View {
    @Environment(Preferences.self) private var preferences
    @State private var cliInstalled = CLIInstaller.isInstalled
    @State private var cliError: String?
    @State private var cliWorking = false

    var body: some View {
        @Bindable var prefs = preferences
        Form {
            Section("Startup") {
                Picker("When BriskEdit opens", selection: $prefs.startupBehavior) {
                    ForEach(Preferences.StartupBehavior.allCases) { behavior in
                        Text(behavior.title).tag(behavior)
                    }
                }
                .pickerStyle(.segmented)
                Text("Restore reopens the last folder and tabs. Start Empty opens a blank workspace, while still remembering the last session for when restore is enabled again.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Section("Command-Line Tool") {
                HStack(alignment: .firstTextBaseline) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Shell command: `briskedit`")
                        Text(cliInstalled
                             ? "Installed. Run `briskedit .` to open a folder. The shorter `brisk` alias is added when that name is free."
                             : "Install `briskedit` to open files and folders from the terminal without replacing existing commands.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer()
                    Button {
                        Task {
                            if cliInstalled { await uninstallCLI() } else { await installCLI() }
                        }
                    } label: {
                        ZStack {
                            // Keep the button width steady so it doesn't jump
                            // when the label swaps for the spinner.
                            Text(cliInstalled ? "Uninstall" : "Install").opacity(cliWorking ? 0 : 1)
                            if cliWorking {
                                ProgressView().controlSize(.small)
                            }
                        }
                        .frame(minWidth: 64)
                    }
                    .disabled(cliWorking)
                    .animation(.easeInOut(duration: 0.15), value: cliWorking)
                }
            }
            Section("Welcome & Setup") {
                HStack(alignment: .firstTextBaseline) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Onboarding")
                        Text("Replay the animated welcome to reconfigure the editor, performance and source-control basics.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer()
                    Button("Show Again") {
                        prefs.hasCompletedOnboarding = false
                        NSApp.keyWindow?.makeKeyAndOrderFront(nil)
                    }
                }
            }
        }
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
        .padding()
        .task { cliInstalled = CLIInstaller.isInstalled }
        .alert("Couldn't install the command", isPresented: Binding(
            get: { cliError != nil },
            set: { if !$0 { cliError = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(cliError ?? "")
        }
    }

    private func installCLI() async {
        cliWorking = true
        let start = Date()
        do {
            try await CLIInstaller.install()
            cliInstalled = CLIInstaller.isInstalled
        } catch CLIInstallerError.authorizationCancelled {
            // The user dismissed the authorization dialog — nothing to report.
        } catch {
            cliError = error.localizedDescription
        }
        await holdSpinner(since: start)
        cliWorking = false
    }

    private func uninstallCLI() async {
        cliWorking = true
        let start = Date()
        do {
            try await CLIInstaller.uninstall()
            cliInstalled = CLIInstaller.isInstalled
        } catch CLIInstallerError.authorizationCancelled {
            // The user dismissed the authorization dialog — nothing to report.
        } catch {
            cliError = error.localizedDescription
        }
        await holdSpinner(since: start)
        cliWorking = false
    }

    /// Keeps the spinner on screen for at least a short beat so a near-instant
    /// install still reads as an action rather than a flicker.
    private func holdSpinner(since start: Date) async {
        let minimum = 0.5
        let elapsed = Date().timeIntervalSince(start)
        if elapsed < minimum {
            try? await Task.sleep(for: .seconds(minimum - elapsed))
        }
    }
}

// MARK: - Appearance

private struct AppearancePreferencesView: View {
    @Environment(Preferences.self) private var preferences
    @Environment(ThemeStore.self) private var themeStore
    @State private var importError: String?
    @State private var fontFamilies: [String] = []

    var body: some View {
        @Bindable var prefs = preferences
        Form {
            Section("Color Theme") {
                Picker("Theme", selection: $prefs.themeID) {
                    ForEach(themeStore.themes) { theme in
                        Text(theme.name).tag(theme.id)
                    }
                }
                if let theme = themeStore.theme(id: prefs.themeID) {
                    ThemePreview(theme: theme)
                        .listRowSeparator(.hidden)
                }
                HStack {
                    Button("Import Theme…") { importTheme() }
                    Spacer()
                    if let theme = themeStore.theme(id: prefs.themeID), !theme.isBuiltIn {
                        Button("Remove", role: .destructive) {
                            themeStore.deleteTheme(id: theme.id)
                            prefs.themeID = "system"
                        }
                    }
                }
                Text("Bring any `.json` color theme over — keywords, types, strings, comments and git colors are mapped automatically.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Section("Font") {
                Picker("Font", selection: $prefs.fontName) {
                    ForEach(fontFamilies, id: \.self) { family in
                        Text(family).font(.custom(family, size: 13)).tag(family)
                    }
                }
                Stepper(value: $prefs.fontSize, in: 9...28, step: 1) {
                    Text("Size: \(Int(prefs.fontSize)) pt")
                }
                Text("Monospaced fonts installed on this Mac. Pick the face you want the editor to render code in.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Section("Editor Chrome") {
                Toggle("Show minimap", isOn: $prefs.showMinimap)
                Text("A zoomed-out overview of the file at the right edge of the editor. Click or drag it to scroll.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Section("Source Control") {
                Toggle("Enable source control", isOn: $prefs.sourceControlEnabled)
                Text("Shows the Source Control sidebar, gutter change bars and inline blame. Turn this off if you don't work in a Git repository.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Toggle("Show git change bars in gutter", isOn: $prefs.showGitGutter)
                    .disabled(!prefs.sourceControlEnabled)
                Toggle("Show inline blame", isOn: $prefs.showInlineGitBlame)
                    .disabled(!prefs.sourceControlEnabled)
            }
        }
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
        .padding()
        .task { fontFamilies = monospacedFamilies(including: preferences.fontName) }
        .alert("Couldn't import theme", isPresented: Binding(
            get: { importError != nil },
            set: { if !$0 { importError = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(importError ?? "")
        }
    }

    @MainActor
    private func importTheme() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [.json]
        panel.message = "Choose a color theme (.json)"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            let theme = try themeStore.importTheme(from: url)
            preferences.themeID = theme.id
        } catch {
            importError = error.localizedDescription
        }
    }
}

/// A one-line code-ish preview that renders the palette's syntax colors so the
/// user sees what a theme looks like before committing to it. Reused by the
/// onboarding editor step.
struct ThemePreview: View {
    let theme: ColorTheme

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 0) {
                token("func ", theme.controlKeyword)
                token("average", theme.function)
                token("(", theme.foreground)
                token("values", theme.foreground)
                token(": ", theme.foreground)
                token("[Double]", theme.type)
                token(") ", theme.foreground)
                token("// mean", theme.comment)
            }
            HStack(spacing: 0) {
                token("  let ", theme.keyword)
                token("n", theme.foreground)
                token(" = ", theme.foreground)
                token("42", theme.number)
                token("  ", theme.foreground)
                token("\"ok\"", theme.string)
            }
        }
        .font(.system(size: 12, design: .monospaced))
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(nsColor: theme.background))
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(.separator))
    }

    private func token(_ text: String, _ color: NSColor) -> some View {
        Text(text).foregroundStyle(Color(nsColor: color))
    }
}

// MARK: - Editor

private struct EditorPreferencesView: View {
    @Environment(Preferences.self) private var preferences

    var body: some View {
        @Bindable var prefs = preferences
        Form {
            Section("Indentation") {
                Stepper(value: $prefs.tabWidth, in: 1...8, step: 1) {
                    Text("Tab width: \(prefs.tabWidth)")
                }
                Toggle("Insert spaces for tab", isOn: $prefs.usesSpacesForTabs)
            }
            Section("On Save") {
                Toggle("Autosave after a short delay", isOn: $prefs.autosave)
                Text("Writes the file to disk about a second after you stop typing. Only applies to files that already have a location.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Toggle("Format with installed tools", isOn: $prefs.formatOnSave)
                Text("Runs clang-format, swift-format, gofmt, rustfmt, black or prettier if present on your PATH. Skipped silently when the tool isn't installed.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Section("Code Assistance") {
                Toggle("Show hover documentation", isOn: $prefs.showHoverTooltips)
                Text("Shows LSP type and documentation popovers when the pointer rests over a symbol.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Toggle("Show code folding controls", isOn: $prefs.showCodeFolding)
                Text("Draws clickable gutter chevrons for indentation-based folding.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
        .padding()
    }
}

// MARK: - Performance

private struct PerformancePreferencesView: View {
    @Environment(Preferences.self) private var preferences

    var body: some View {
        @Bindable var prefs = preferences
        Form {
            Section("Performance Mode") {
                Picker("Mode", selection: $prefs.performanceMode) {
                    ForEach(Preferences.PerformanceMode.allCases) { mode in
                        Text(mode.title).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()

                VStack(alignment: .leading, spacing: 12) {
                    ForEach(Preferences.PerformanceMode.allCases) { mode in
                        let isSelected = mode == preferences.performanceMode
                        HStack(alignment: .top, spacing: 9) {
                            Image(systemName: mode.systemImage)
                                .foregroundStyle(isSelected ? Color.accentColor : .secondary)
                                .frame(width: 18)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(mode.title)
                                    .font(.callout.weight(isSelected ? .semibold : .regular))
                                Text(mode.explanation)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                    }
                }
                .padding(.top, 2)

                if preferences.performanceMode == .adaptive {
                    Label(
                        "Right now: \(preferences.resolvedPerformanceMode.title) — \(adaptiveReason)",
                        systemImage: preferences.resolvedPerformanceMode.systemImage
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
            }
        }
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
        .padding()
    }

    private var adaptiveReason: String {
        if preferences.isLowPowerModeActive { return "macOS Low Power Mode is on." }
        switch preferences.thermalState {
        case .serious, .critical: return "the Mac is under thermal pressure."
        default: return "running at full speed."
        }
    }
}

// MARK: - Terminal

private struct TerminalPreferencesView: View {
    @Environment(Preferences.self) private var preferences
    /// Installed fixed-pitch font families — the same set Terminal.app offers.
    @State private var families: [String] = []

    var body: some View {
        @Bindable var prefs = preferences
        Form {
            Section("Font") {
                Picker("Font", selection: $prefs.terminalFontName) {
                    ForEach(families, id: \.self) { family in
                        Text(family).font(.custom(family, size: 13)).tag(family)
                    }
                }
                Stepper(value: $prefs.terminalFontSize, in: 9...28, step: 1) {
                    Text("Size: \(Int(prefs.terminalFontSize)) pt")
                }
                Text("Monospaced fonts installed on this Mac — the same list Terminal.app uses. Pick the one from your Terminal profile (e.g. “MesloLGS Nerd Font”) so powerline prompts and glyphs render correctly.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Section("Keyboard") {
                Toggle("Use Option as Meta key", isOn: $prefs.terminalOptionAsMeta)
                Text("Off: ⌥ types layout characters — needed for `@`, `{`, `}`, `|`, `~` on international layouts (e.g. German ⌥L = @). On: ⌥ acts as Meta (⌥-key sends ESC-key) for Emacs-style shortcuts.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
        .padding()
        .task { families = monospacedFamilies(including: prefs.terminalFontName) }
    }
}

/// Fixed-pitch font *family* names, sorted. Always includes the current
/// selection so a previously-saved font that isn't fixed-pitch still appears.
/// Shared by the editor (Appearance) and terminal font pickers.
@MainActor
private func monospacedFamilies(including current: String) -> [String] {
    let manager = NSFontManager.shared
    var names = Set<String>()
    for fontName in manager.availableFontNames(with: .fixedPitchFontMask) ?? [] {
        if let family = NSFont(name: fontName, size: 12)?.familyName {
            names.insert(family)
        }
    }
    names.insert(current)
    return names.sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
}

// MARK: - Updates

private struct UpdatePreferencesView: View {
    @Environment(UpdateService.self) private var updates

    var body: some View {
        @Bindable var updates = updates
        Form {
            Section("Version") {
                LabeledContent("Installed", value: Self.versionString)
                if updates.isUpdateAvailable, let available = updates.availableUpdateVersion {
                    LabeledContent("Available") {
                        HStack(spacing: 6) {
                            Image(systemName: "arrow.down.circle.fill").foregroundStyle(.tint)
                            Text(available)
                        }
                    }
                }
            }
            Section("Channel") {
                Picker("Update channel", selection: $updates.channel) {
                    ForEach(UpdateService.Channel.allCases) { channel in
                        Text(channel.displayName).tag(channel)
                    }
                }
                .pickerStyle(.segmented)
            }
            Section("Automatic checks") {
                Toggle("Check for updates automatically", isOn: $updates.automaticallyChecksForUpdates)
                Text("On by default — BriskEdit checks in the background and on launch. Turn this off to only check manually.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if let date = updates.lastCheckDate {
                    LabeledContent("Last check", value: date.formatted(date: .abbreviated, time: .shortened))
                }
            }
            Section {
                Button("Check Now") { updates.checkForUpdates() }
            }
        }
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
        .padding()
    }

    /// "0.3.0 (1)" from the bundle's marketing version and build number.
    private static var versionString: String {
        let info = Bundle.main.infoDictionary
        let short = info?["CFBundleShortVersionString"] as? String ?? "—"
        let build = info?["CFBundleVersion"] as? String ?? "—"
        return "\(short) (\(build))"
    }
}

// MARK: - Experimental

/// Opt-in features that aren't part of the core editor experience yet. Each is
/// presented as a self-contained card the user explicitly switches on.
private struct ExperimentalPreferencesView: View {
    @Environment(Preferences.self) private var preferences

    var body: some View {
        @Bindable var prefs = preferences
        Form {
            Section {
                ExperimentalCard(
                    title: "Discord Rich Presence",
                    systemImage: "gamecontroller",
                    summary: "Show what you're working on — the file, its language and the workspace — on your Discord profile.",
                    isOn: $prefs.discordRichPresence
                ) {
                    Toggle("Show file name", isOn: $prefs.discordShowFileName)
                    Text("Off hides the file name and shows only the language (\u{201C}Editing a Swift file\u{201D}) — handy for private repositories.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Toggle("Show workspace name", isOn: $prefs.discordShowWorkspace)
                    Toggle("Show elapsed time", isOn: $prefs.discordShowElapsed)
                }
            } footer: {
                Text("Requires the desktop Discord app to be running. Nothing leaves your Mac except the file/language/workspace names you choose to show.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
        .padding()
    }
}

/// A framed experimental feature: a header with an enable toggle, plus options
/// that reveal only once the feature is switched on.
private struct ExperimentalCard<Options: View>: View {
    let title: String
    let systemImage: String
    let summary: String
    @Binding var isOn: Bool
    @ViewBuilder let options: () -> Options

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Toggle(isOn: $isOn) {
                HStack(spacing: 8) {
                    Image(systemName: systemImage)
                        .foregroundStyle(.tint)
                    Text(title).font(.headline)
                    Text("Experimental")
                        .font(.caption2.weight(.semibold))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(.orange.opacity(0.18), in: Capsule())
                        .foregroundStyle(.orange)
                }
            }
            .toggleStyle(.switch)

            Text(summary)
                .font(.callout)
                .foregroundStyle(.secondary)

            if isOn {
                Divider()
                VStack(alignment: .leading, spacing: 6) {
                    options()
                }
                .transition(.opacity)
            }
        }
        .padding(4)
        .animation(.easeInOut(duration: 0.15), value: isOn)
    }
}

// MARK: - About

/// App identity: icon, name, author + license, version, and links back to the
/// project. The credit and license mirror the welcome screen and the `LICENSE`
/// file (MIT, © Johannes Grof).
private struct AboutPreferencesView: View {
    private static let repoURL = "https://github.com/jx-grxf/BriskEdit"
    private static let issuesURL = "https://github.com/jx-grxf/BriskEdit/issues"

    private var versionLabel: String {
        let info = Bundle.main.infoDictionary
        let short = info?["CFBundleShortVersionString"] as? String ?? "1.0"
        let build = info?["CFBundleVersion"] as? String ?? "1"
        return "Version \(short) (\(build))"
    }

    var body: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 0)

            Image(nsImage: NSApplication.shared.applicationIconImage)
                .resizable()
                .frame(width: 96, height: 96)
                .accessibilityHidden(true)

            Text("BriskEdit")
                .font(.system(size: 26, weight: .bold))
                .padding(.top, 10)
            Text("Johannes Grof · MIT")
                .font(.callout)
                .foregroundStyle(.secondary)
                .padding(.top, 2)
            Text(versionLabel)
                .font(.caption)
                .foregroundStyle(.tertiary)
                .padding(.top, 2)

            Text("A native macOS code editor — no Electron, no extension runtime, zero-config.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 16)
                .padding(.horizontal, 50)

            HStack(spacing: 10) {
                Button {
                    open(Self.repoURL)
                } label: {
                    Label("GitHub Repository", systemImage: "chevron.left.forwardslash.chevron.right")
                }
                Button {
                    open(Self.issuesURL)
                } label: {
                    Label("Report an Issue", systemImage: "ladybug")
                }
            }
            .buttonStyle(.link)
            .padding(.top, 20)

            Text("© 2026 Johannes Grof")
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .padding(.top, 18)

            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(24)
    }

    private func open(_ string: String) {
        if let url = URL(string: string) { NSWorkspace.shared.open(url) }
    }
}
