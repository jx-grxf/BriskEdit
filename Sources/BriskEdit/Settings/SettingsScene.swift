import AppKit
import SwiftUI

struct SettingsScene: View {
    var body: some View {
        TabView {
            AppearancePreferencesView()
                .tabItem { Label("Appearance", systemImage: "paintpalette") }
            EditorPreferencesView()
                .tabItem { Label("Editor", systemImage: "text.cursor") }
            TerminalPreferencesView()
                .tabItem { Label("Terminal", systemImage: "terminal") }
            UpdatePreferencesView()
                .tabItem { Label("Updates", systemImage: "arrow.triangle.2.circlepath") }
        }
        .frame(width: 520, height: 440)
    }
}

// MARK: - Appearance

private struct AppearancePreferencesView: View {
    @Environment(Preferences.self) private var preferences
    @Environment(ThemeStore.self) private var themeStore
    @State private var importError: String?

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
                Stepper(value: $prefs.fontSize, in: 9...28, step: 1) {
                    Text("Size: \(Int(prefs.fontSize)) pt")
                }
                TextField("Font name", text: $prefs.fontName)
                let installed = NSFont(name: prefs.fontName, size: prefs.fontSize) != nil
                if !installed {
                    Text("“\(prefs.fontName)” isn't installed — falling back to the system monospaced font.")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
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
        .padding()
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
        .padding()
    }
}

// MARK: - Terminal

private struct TerminalPreferencesView: View {
    @Environment(Preferences.self) private var preferences

    var body: some View {
        @Bindable var prefs = preferences
        Form {
            Section("Font") {
                TextField("Font name", text: $prefs.terminalFontName)
                Stepper(value: $prefs.terminalFontSize, in: 9...28, step: 1) {
                    Text("Size: \(Int(prefs.terminalFontSize)) pt")
                }
                let installed = NSFont(name: prefs.terminalFontName, size: prefs.terminalFontSize) != nil
                    || NSFontManager.shared.availableFontFamilies.contains(prefs.terminalFontName)
                Text(installed
                    ? "Match your Terminal.app profile, e.g. “MesloLGS Nerd Font”, so powerline prompts and glyphs render correctly."
                    : "“\(prefs.terminalFontName)” isn't installed — falling back to the system monospaced font.")
                    .font(.caption)
                    .foregroundStyle(installed ? Color.secondary : Color.orange)
            }
        }
        .formStyle(.grouped)
        .padding()
    }
}

// MARK: - Updates

private struct UpdatePreferencesView: View {
    @Environment(UpdateService.self) private var updates

    var body: some View {
        @Bindable var updates = updates
        Form {
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
        .padding()
    }
}
