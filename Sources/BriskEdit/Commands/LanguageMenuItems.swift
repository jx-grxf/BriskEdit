import SwiftUI

/// The contents of the "Language" menu, shared by the View menu (`AppCommands`)
/// and the status-bar `LanguagePicker` so both stay in sync: an "Auto-detect"
/// entry that clears the manual choice, then every supported syntax with a
/// checkmark on the active one.
struct LanguageMenuItems: View {
    let document: TextDocument

    var body: some View {
        Button(action: resetToAutoDetect) {
            Label("Auto-detect (\(document.detectedLanguage.rawValue))",
                  systemImage: document.languageOverride == nil ? "checkmark" : "wand.and.stars")
        }
        Divider()
        ForEach(SourceLanguage.allCases) { language in
            Button {
                document.languageOverride = language
            } label: {
                if document.language == language {
                    Label(language.rawValue, systemImage: "checkmark")
                } else {
                    Text(language.rawValue)
                }
            }
        }
    }

    private func resetToAutoDetect() {
        document.languageOverride = nil
    }
}
