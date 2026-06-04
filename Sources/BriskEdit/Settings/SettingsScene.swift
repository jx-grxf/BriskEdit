import AppKit
import SwiftUI

struct SettingsScene: View {
    var body: some View {
        TabView {
            GeneralPreferencesView()
                .tabItem { Label("General", systemImage: "gearshape") }
            AppearancePreferencesView()
                .tabItem { Label("Appearance", systemImage: "paintpalette") }
            EditorPreferencesView()
                .tabItem { Label("Editor", systemImage: "text.cursor") }
            TerminalPreferencesView()
                .tabItem { Label("Terminal", systemImage: "terminal") }
            UpdatePreferencesView()
                .tabItem { Label("Updates", systemImage: "arrow.triangle.2.circlepath") }
        }
        .frame(width: 520, height: 480)
    }
}

// MARK: - General

private struct GeneralPreferencesView: View {
    @Environment(Preferences.self) private var preferences

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
        }
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
        .padding()
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
                    Button("Import VS Code Theme…") { importTheme() }
                    Spacer()
                    if let theme = themeStore.theme(id: prefs.themeID), !theme.isBuiltIn {
                        Button("Remove", role: .destructive) {
                            themeStore.deleteTheme(id: theme.id)
                            prefs.themeID = "system"
                        }
                    }
                }
                Text("Bring any VS Code `.json` color theme over — keywords, types, strings, comments and git colors are mapped automatically.")
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
                Toggle("Show git change bars in gutter", isOn: $prefs.showGitGutter)
                Text("The colored bars next to the line numbers mark lines added, modified or deleted since the last commit.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
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
        panel.message = "Choose a VS Code color theme (.json)"
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
/// user sees what a theme looks like before committing to it.
private struct ThemePreview: View {
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
