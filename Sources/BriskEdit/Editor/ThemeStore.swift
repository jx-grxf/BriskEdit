import AppKit
import Foundation
import Observation

/// Holds the editor color themes: the built-ins plus any VS Code themes the
/// user imported. Imported themes are persisted as small JSON snapshots under
/// `Application Support/BriskEdit/Themes` and reloaded on launch.
@MainActor
@Observable
final class ThemeStore {
    static let shared = ThemeStore()

    private(set) var imported: [ColorTheme] = []

    /// Built-ins first, then imported themes (alphabetical).
    var themes: [ColorTheme] {
        ColorTheme.builtIns + imported.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    private let directory: URL

    init(directory: URL? = nil) {
        self.directory = directory ?? Self.defaultDirectory()
        loadImported()
    }

    func theme(id: String) -> ColorTheme? {
        themes.first { $0.id == id }
    }

    /// Imports a VS Code `.json`/`.jsonc` color theme, persists it and returns
    /// the parsed theme so callers can select it immediately.
    @discardableResult
    func importTheme(from url: URL) throws -> ColorTheme {
        let data = try Data(contentsOf: url)
        let baseName = url.deletingPathExtension().lastPathComponent
        let id = "imported." + slug(baseName)
        let theme = try VSCodeThemeImporter.theme(fromJSON: data, id: id, fallbackName: baseName)

        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let dest = directory.appendingPathComponent(id + ".json")
        let encoded = try JSONEncoder().encode(ColorThemeData(theme))
        try encoded.write(to: dest, options: .atomic)

        imported.removeAll { $0.id == id }
        imported.append(theme)
        return theme
    }

    func deleteTheme(id: String) {
        guard imported.contains(where: { $0.id == id }) else { return }
        imported.removeAll { $0.id == id }
        try? FileManager.default.removeItem(at: directory.appendingPathComponent(id + ".json"))
    }

    // MARK: - Persistence

    private func loadImported() {
        guard let files = try? FileManager.default.contentsOfDirectory(
            at: directory, includingPropertiesForKeys: nil
        ) else { return }
        let decoder = JSONDecoder()
        imported = files
            .filter { $0.pathExtension == "json" }
            .compactMap { try? decoder.decode(ColorThemeData.self, from: Data(contentsOf: $0)) }
            .map(\.theme)
    }

    private static func defaultDirectory() -> URL {
        let base = (try? FileManager.default.url(
            for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: false
        )) ?? URL(fileURLWithPath: NSTemporaryDirectory())
        return base.appendingPathComponent("BriskEdit/Themes", isDirectory: true)
    }

    private func slug(_ name: String) -> String {
        let allowed = name.lowercased().map { $0.isLetter || $0.isNumber ? $0 : "-" }
        let slug = String(allowed).split(separator: "-").joined(separator: "-")
        return slug.isEmpty ? "theme" : slug
    }
}
