import AppKit
import SwiftUI

struct SettingsScene: View {
    var body: some View {
        TabView {
            EditorPreferencesView()
                .tabItem { Label("Editor", systemImage: "text.cursor") }
            TerminalPreferencesView()
                .tabItem { Label("Terminal", systemImage: "terminal") }
            UpdatePreferencesView()
                .tabItem { Label("Updates", systemImage: "arrow.triangle.2.circlepath") }
        }
        .frame(width: 480, height: 340)
    }
}

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

private struct EditorPreferencesView: View {
    @Environment(Preferences.self) private var preferences

    var body: some View {
        @Bindable var prefs = preferences
        Form {
            Section("Font") {
                Stepper(value: $prefs.fontSize, in: 9...28, step: 1) {
                    Text("Size: \(Int(prefs.fontSize)) pt")
                }
                TextField("Font name", text: $prefs.fontName)
            }
            Section("Indentation") {
                Stepper(value: $prefs.tabWidth, in: 1...8, step: 1) {
                    Text("Tab width: \(prefs.tabWidth)")
                }
                Toggle("Insert spaces for tab", isOn: $prefs.usesSpacesForTabs)
            }
            Section("Source Control") {
                Toggle("Show git change bars in gutter", isOn: $prefs.showGitGutter)
                Text("The colored bars next to the line numbers mark lines added, modified or deleted since the last commit.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
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
        }
        .formStyle(.grouped)
        .padding()
    }
}
