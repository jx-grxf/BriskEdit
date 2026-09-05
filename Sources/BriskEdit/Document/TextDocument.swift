import Foundation
import Observation

@MainActor
@Observable
final class TextDocument {
    nonisolated static let largeFileFeatureThresholdBytes = 4 * 1024 * 1024
    nonisolated static let maximumEditableFileBytes: Int64 = 128 * 1024 * 1024
    private(set) var fileURL: URL?
    private(set) var encoding: String.Encoding
    private(set) var text: String
    private(set) var byteCount: Int
    var isDirty: Bool = false
    var cursorLine: Int = 1
    var cursorColumn: Int = 1
    /// Set when the file changed on disk while this buffer still had unsaved
    /// edits — the UI offers a reload instead of silently dropping either side.
    var externalChangePending: Bool = false
    /// Latest compiler/LSP findings, shown as gutter markers.
    var diagnostics: [Diagnostic] = []
    /// Bumped on every text mutation so the editor can detect *external* changes
    /// cheaply, instead of comparing entire (possibly huge) strings each update.
    private(set) var revision: Int = 0
    private var lastSavedRevision: Int = 0
    /// A request to scroll to and select a range, set by navigation features
    /// (Find in Files, symbol outline, go-to-definition). The editor consumes it
    /// when `revealToken` changes, mirroring the `revision` pattern.
    private(set) var pendingReveal: PendingReveal?
    private(set) var revealToken: Int = 0
    private var lineStartOffsets: [Int] = [0]
    private var lineIndexWork: DispatchWorkItem?
    private var autosaveWork: DispatchWorkItem?
    private var recoveryTask: Task<Void, Never>?
    private var recoveryGeneration = 0
    let recoveryID: UUID
    private var isClosedForSaves = false
    /// Called when a deferred autosave fails so the owning workspace can raise
    /// its usual save-failure message instead of dropping the error.
    var autosaveFailureHandler: ((Error) -> Void)?
    /// Size and modification date observed right after our own write landed;
    /// lets the file watcher tell self-initiated saves from external edits.
    private(set) var lastSelfWriteInfo: (modificationDate: Date, size: Int)?
    /// Tail of the write chain. Each new write awaits the previous one so two
    /// in-flight writes (autosave racing a manual ⌘S) can never reorder and
    /// leave older content on disk.
    private var lastWriteTask: Task<Void, Error>?
    private var isRelocating = false

    var displayName: String {
        fileURL?.lastPathComponent ?? "Untitled"
    }

    /// User-chosen language from the status-bar/menu picker. When nil the
    /// language is auto-detected from the file name/extension.
    var languageOverride: SourceLanguage?

    var language: SourceLanguage {
        languageOverride ?? SourceLanguage(url: fileURL, displayName: displayName)
    }

    /// The language that auto-detection would pick, ignoring any manual override.
    var detectedLanguage: SourceLanguage {
        SourceLanguage(url: fileURL, displayName: displayName)
    }

    /// Exact UTF-8 byte count shown in the status bar. Computing it walks the
    /// whole buffer, so while typing it lags `revision` and is refreshed on a
    /// short debounce instead of on every keystroke. `byteCount` stays the
    /// cheap UTF-16 estimate backing the large-file gate.
    private var displayedByteCount: Int
    private var displayedByteCountRevision: Int
    private var byteCountWork: DispatchWorkItem?
    /// Cached `ByteCountFormatter` output for the current `displayedByteCount`;
    /// re-formatted only when the displayed count actually changes.
    private var fileSizeLabelText: String?

    var fileSizeLabel: String {
        if displayedByteCountRevision != revision {
            scheduleByteCountRefresh()
        }
        if let cached = fileSizeLabelText {
            return cached
        }
        let label = ByteCountFormatter.string(fromByteCount: Int64(displayedByteCount), countStyle: .file)
        fileSizeLabelText = label
        return label
    }

    private func scheduleByteCountRefresh() {
        byteCountWork?.cancel()
        let work = DispatchWorkItem { [weak self] in
            Task { @MainActor [weak self] in
                guard let self, self.displayedByteCountRevision != self.revision else { return }
                self.displayedByteCount = self.text.utf8.count
                self.displayedByteCountRevision = self.revision
                self.fileSizeLabelText = nil
            }
        }
        byteCountWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5, execute: work)
    }

    var isLargeFile: Bool {
        Self.isLargeFile(byteCount: byteCount)
    }

    nonisolated static func isLargeFile(byteCount: Int) -> Bool {
        byteCount > largeFileFeatureThresholdBytes
    }

    init(fileURL: URL?, text: String, encoding: String.Encoding, byteCount: Int? = nil, recoveryID: UUID = UUID()) {
        let exactBytes = byteCount ?? text.utf8.count
        self.fileURL = fileURL
        self.text = text
        self.encoding = encoding
        self.byteCount = exactBytes
        self.displayedByteCount = exactBytes
        self.displayedByteCountRevision = 0
        self.recoveryID = recoveryID
        if !isLargeFile {
            rebuildLineIndex()
        }
    }

    static func empty() -> TextDocument {
        TextDocument(fileURL: nil, text: "", encoding: .utf8)
    }

    static func recovered(_ draft: RecoverableDraft) -> TextDocument {
        let document = TextDocument(fileURL: nil, text: draft.text,
                                    encoding: String.Encoding(rawValue: draft.encodingRawValue),
                                    recoveryID: draft.id)
        document.isDirty = true
        document.revision = 1
        document.scheduleRecoverySnapshot()
        return document
    }

    static func load(from url: URL) async throws -> TextDocument {
        let loaded = try await Task.detached(priority: .userInitiated) { () -> (String, String.Encoding, Int) in
            let values = try url.resourceValues(forKeys: [.fileSizeKey])
            if let size = values.fileSize, Int64(size) > Self.maximumEditableFileBytes {
                throw TextDocumentError.fileTooLarge(maximumBytes: Self.maximumEditableFileBytes)
            }
            var used: String.Encoding = .utf8
            let str = try String(contentsOf: url, usedEncoding: &used)
            return (str, used, values.fileSize ?? str.utf8.count)
        }.value
        return TextDocument(fileURL: url, text: loaded.0, encoding: loaded.1, byteCount: loaded.2)
    }

    func applyEdit(text newText: String, sizeHint: Int? = nil) {
        guard text != newText else { return }
        text = newText
        byteCount = sizeHint ?? newText.utf8.count
        revision &+= 1
        isDirty = true
        scheduleLineIndexRebuild()
        scheduleAutosave()
        scheduleRecoverySnapshot()
    }

    /// "After delay" autosave: writes the buffer to disk ~1 s after the last
    /// edit, when enabled and the document is file-backed. Untitled
    /// documents are skipped (no path to write to, and we don't pop a panel mid-
    /// typing). Plain save — no format-on-save, so the buffer isn't mutated while
    /// the user is typing.
    private func scheduleAutosave() {
        autosaveWork?.cancel()
        guard fileURL != nil, UserDefaults.standard.bool(forKey: "editor.autosave") else { return }
        let work = DispatchWorkItem { [weak self] in
            guard let self, !isClosedForSaves, !isRelocating, !externalChangePending, isDirty, fileURL != nil else { return }
            Task { @MainActor in await self.performAutosave() }
        }
        autosaveWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0, execute: work)
    }

    private func performAutosave() async {
        guard !isClosedForSaves, !isRelocating, !externalChangePending else { return }
        do {
            try await save(respectingCloseGuard: true)
        } catch {
            autosaveFailureHandler?(error)
        }
    }

    /// Cancels all deferred writes because the owning tab just closed. An
    /// autosave scheduled before "Don't Save" must never land on disk.
    func invalidatePendingSaves() {
        isClosedForSaves = true
        autosaveWork?.cancel()
        autosaveWork = nil
    }

    private var draftRecoveryEnabled: Bool {
        if ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
            || NSClassFromString("XCTestCase") != nil { return false }
        let defaults = UserDefaults.standard
        return defaults.object(forKey: "editor.draftRecoveryEnabled") == nil
            || defaults.bool(forKey: "editor.draftRecoveryEnabled")
    }

    private func scheduleRecoverySnapshot() {
        recoveryTask?.cancel()
        guard draftRecoveryEnabled else { discardRecoverySnapshot(); return }
        guard isDirty else { return }
        // The editor provides a cheap UTF-16 size hint. Reject obviously large
        // buffers here; exact UTF-8 validation belongs to the off-main store.
        guard byteCount <= DraftRecoveryStore.maximumDraftBytes else { return }
        recoveryGeneration &+= 1
        let generation = recoveryGeneration
        let snapshot = text
        let url = fileURL
        let name = displayName
        let id = recoveryID
        let encoding = encoding
        recoveryTask = Task { [weak self] in
            do {
                try await Task.sleep(for: .seconds(1))
                guard !Task.isCancelled else { return }
                do { try await DraftRecoveryStore.shared.save(id: id, generation: generation, fileURL: url, displayName: name, text: snapshot, encoding: encoding) }
                catch { await MainActor.run { self?.autosaveFailureHandler?(error) } }
            } catch { return }
        }
    }

    func discardRecoverySnapshot() {
        recoveryTask?.cancel()
        recoveryTask = nil
        recoveryGeneration &+= 1
        let generation = recoveryGeneration
        let id = recoveryID
        recoveryTask = Task { try? await DraftRecoveryStore.shared.remove(id: id, generation: generation) }
    }

    func flushRecoveryChanges() async {
        await recoveryTask?.value
    }

    func persistRecoverySnapshotNow(minimumGeneration: Int = 0, store: DraftRecoveryStore = .shared) async throws {
        recoveryTask?.cancel()
        recoveryGeneration = max(recoveryGeneration + 1, minimumGeneration)
        try await store.save(id: recoveryID, generation: recoveryGeneration,
            fileURL: fileURL, displayName: displayName, text: text, encoding: encoding)
    }

    /// Small files rebuild the line index immediately (exact Ln/Col); large files
    /// debounce it so typing in a 20 MB file stays smooth.
    private func scheduleLineIndexRebuild() {
        lineIndexWork?.cancel()
        if (text as NSString).length <= 100_000 {
            rebuildLineIndex()
            return
        }
        // Large/medium buffers: scan newlines off the main thread, debounced, so
        // typing stays smooth while Ln/Col in the status bar stay correct (even in
        // large-file mode, where running this on the main actor would stall).
        let snapshot = text
        let revisionAtSchedule = revision
        let work = DispatchWorkItem { [weak self] in
            let offsets = TextDocument.computeLineStartOffsets(in: snapshot)
            Task { @MainActor [weak self] in
                guard let self, self.revision == revisionAtSchedule else { return }
                self.lineStartOffsets = offsets
            }
        }
        lineIndexWork = work
        DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + 0.25, execute: work)
    }

    /// Points the document at a new on-disk location (e.g. after a rename)
    /// without touching the buffer or dirty state.
    func retarget(to url: URL) {
        fileURL = url
    }

    /// Replaces the buffer with formatter output just before a save. Bumps
    /// `revision` so the editor re-seeds; the following save clears dirty state.
    func applyFormatted(_ newText: String) {
        guard newText != text else { return }
        text = newText
        byteCount = newText.utf8.count
        revision &+= 1
        displayedByteCount = byteCount
        displayedByteCountRevision = revision
        fileSizeLabelText = nil
        isDirty = true
        scheduleLineIndexRebuild()
        scheduleRecoverySnapshot()
    }

    /// Re-reads the file from disk after an external change. Bumps `revision`
    /// so the editor re-seeds its text view, and clears dirty/pending state.
    func reloadFromDisk() async {
        guard let url = fileURL else { return }
        let revisionAtStart = revision
        let loaded = try? await Task.detached(priority: .userInitiated) { () -> (String, String.Encoding) in
            let values = try url.resourceValues(forKeys: [.fileSizeKey])
            if let size = values.fileSize, Int64(size) > Self.maximumEditableFileBytes {
                throw TextDocumentError.fileTooLarge(maximumBytes: Self.maximumEditableFileBytes)
            }
            var used: String.Encoding = .utf8
            let str = try String(contentsOf: url, usedEncoding: &used)
            return (str, used)
        }.value
        guard let loaded else { return }
        guard revision == revisionAtStart else {
            // The user typed while the read was in flight; don't clobber those
            // edits or mark them clean — offer the reload banner instead.
            externalChangePending = true
            return
        }
        text = loaded.0
        encoding = loaded.1
        revision &+= 1
        byteCount = loaded.0.utf8.count
        displayedByteCount = byteCount
        displayedByteCountRevision = revision
        fileSizeLabelText = nil
        isDirty = false
        lastSavedRevision = revision
        externalChangePending = false
        discardRecoverySnapshot()
        scheduleLineIndexRebuild()
    }

    /// Asks the editor to scroll to and select `length` characters starting at a
    /// 1-based line/column. Length 0 just places the caret there.
    func requestReveal(line: Int, column: Int = 1, length: Int = 0) {
        pendingReveal = PendingReveal(line: line, column: column, length: length)
        revealToken &+= 1
    }

    /// UTF-16 range for a 1-based line/column with a given length, clamped to the
    /// buffer. Used to turn a navigation target into an `NSTextView` selection.
    func range(line: Int, column: Int, length: Int) -> NSRange {
        let nsString = text as NSString
        let lineIndex = max(0, line - 1)
        guard lineIndex < lineStartOffsets.count else {
            return NSRange(location: nsString.length, length: 0)
        }
        let location = min(lineStartOffsets[lineIndex] + max(0, column - 1), nsString.length)
        let clampedLength = max(0, min(length, nsString.length - location))
        return NSRange(location: location, length: clampedLength)
    }

    func updateCursor(location: Int) {
        let safeLocation = max(0, min(location, text.utf16.count))
        var low = 0
        var high = lineStartOffsets.count
        while low < high {
            let mid = (low + high) / 2
            if lineStartOffsets[mid] <= safeLocation {
                low = mid + 1
            } else {
                high = mid
            }
        }
        let lineIndex = max(0, low - 1)
        cursorLine = lineIndex + 1
        cursorColumn = safeLocation - lineStartOffsets[lineIndex] + 1
    }

    func save() async throws {
        guard !externalChangePending else { throw TextDocumentError.externalChangeConflict }
        try await save(respectingCloseGuard: false)
    }

    /// Explicit conflict resolution chosen by the user. This is the only path
    /// allowed to replace a newer on-disk version with the current buffer.
    func overwriteExternalChange() async throws {
        try await save(respectingCloseGuard: false, allowingExternalOverwrite: true)
        externalChangePending = false
    }

    func save(respectingCloseGuard: Bool, allowingExternalOverwrite: Bool = false) async throws {
        guard let url = fileURL else { throw CocoaError(.fileWriteUnknown) }
        guard allowingExternalOverwrite || !externalChangePending else { throw TextDocumentError.externalChangeConflict }
        let savedRevision = try await write(to: url, encoding: encoding, respectingCloseGuard: respectingCloseGuard)
        finishSave(revision: savedRevision)
    }

    func save(to url: URL) async throws {
        let savedRevision = try await write(to: url, encoding: encoding, respectingCloseGuard: false)
        fileURL = url
        finishSave(revision: savedRevision)
    }

    private func finishSave(revision savedRevision: Int) {
        lastSavedRevision = savedRevision
        if revision == savedRevision {
            isDirty = false
            discardRecoverySnapshot()
        }
        NotificationCenter.default.post(name: .gitDidChange, object: nil)
    }

    private func write(to url: URL, encoding: String.Encoding, respectingCloseGuard: Bool) async throws -> Int {
        if respectingCloseGuard && isClosedForSaves { throw CancellationError() }
        if isRelocating { throw TextDocumentError.relocationInProgress }
        let snapshot = text
        let snapshotRevision = revision
        let previous = lastWriteTask
        let task = Task.detached(priority: .userInitiated) { [snapshot, encoding] in
            // A failed earlier write doesn't block this one — every write
            // carries a complete snapshot; only the ordering matters.
            _ = try? await previous?.value
            try snapshot.write(to: url, atomically: true, encoding: encoding)
        }
        lastWriteTask = task
        try await task.value
        recordSelfWrite(at: url)
        return snapshotRevision
    }

    /// Quiesces the write chain before a file-system rename/move. While this
    /// lease is held new writes fail rather than recreating the old path.
    func beginRelocation() async throws {
        guard !isRelocating else { throw TextDocumentError.relocationInProgress }
        isRelocating = true
        autosaveWork?.cancel()
        autosaveWork = nil
        do { try await lastWriteTask?.value } catch {
            isRelocating = false
            throw error
        }
    }

    func finishRelocation(to url: URL) {
        fileURL = url
        isRelocating = false
        if isDirty { scheduleAutosave() }
    }

    func cancelRelocation() {
        isRelocating = false
        if isDirty { scheduleAutosave() }
    }

    private func recordSelfWrite(at url: URL) {
        if let attributes = try? FileManager.default.attributesOfItem(atPath: url.path),
           let modified = attributes[.modificationDate] as? Date,
           let size = attributes[.size] as? Int {
            lastSelfWriteInfo = (modificationDate: modified, size: size)
        }
    }

    private func rebuildLineIndex() {
        lineStartOffsets = Self.computeLineStartOffsets(in: text)
    }

    /// Pure newline scan — safe to run off the main actor for large buffers.
    nonisolated static func computeLineStartOffsets(in text: String) -> [Int] {
        var starts = [0]
        let nsString = text as NSString
        nsString.enumerateSubstrings(
            in: NSRange(location: 0, length: nsString.length),
            options: [.byLines, .substringNotRequired]
        ) { _, _, enclosingRange, _ in
            let next = NSMaxRange(enclosingRange)
            if next < nsString.length {
                starts.append(next)
            }
        }
        return starts
    }
}

enum TextDocumentError: LocalizedError {
    case fileTooLarge(maximumBytes: Int64)
    case externalChangeConflict
    case relocationInProgress

    var errorDescription: String? {
        switch self {
        case .fileTooLarge(let maximumBytes):
            let limit = ByteCountFormatter.string(fromByteCount: maximumBytes, countStyle: .file)
            return "The file is larger than BriskEdit's \(limit) editing safety limit."
        case .externalChangeConflict:
            return "The file changed on disk. Choose whether to reload it or overwrite the external version."
        case .relocationInProgress:
            return "The file is being moved. Try saving again when the move finishes."
        }
    }
}

/// A navigation target handed from a feature (search, outline, definition) to
/// the editor: scroll to and select `length` chars at a 1-based line/column.
struct PendingReveal: Equatable, Sendable {
    var line: Int
    var column: Int
    var length: Int
}

enum SourceLanguage: String, Sendable, CaseIterable, Identifiable {
    var id: String { rawValue }

    case c = "C"
    case cpp = "C++"
    case css = "CSS"
    case dart = "Dart"
    case go = "Go"
    case html = "HTML"
    case ini = "INI"
    case java = "Java"
    case javascript = "JavaScript"
    case json = "JSON"
    case kotlin = "Kotlin"
    case less = "Less"
    case lua = "Lua"
    case markdown = "Markdown"
    case perl = "Perl"
    case php = "PHP"
    case python = "Python"
    case ruby = "Ruby"
    case rust = "Rust"
    case scss = "SCSS"
    case shell = "Shell"
    case sql = "SQL"
    case swift = "Swift"
    case toml = "TOML"
    case typescript = "TypeScript"
    case xml = "XML"
    case yaml = "YAML"
    case plainText = "Plain Text"

    init(url: URL?, displayName: String) {
        let ext = (url?.pathExtension.isEmpty == false ? url?.pathExtension : (displayName as NSString).pathExtension)?.lowercased() ?? ""
        // A few files are identified by name, not extension.
        let name = ((url?.lastPathComponent ?? displayName) as NSString).lastPathComponent.lowercased()
        switch name {
        case "makefile", "dockerfile": self = .shell; return
        case ".gitconfig", ".npmrc", ".editorconfig": self = .ini; return
        default: break
        }
        switch ext {
        case "c", "h": self = .c
        case "cc", "cpp", "cxx", "hpp", "hh": self = .cpp
        case "css": self = .css
        case "dart": self = .dart
        case "go": self = .go
        case "htm", "html": self = .html
        case "ini", "cfg", "conf", "properties": self = .ini
        case "java": self = .java
        case "js", "jsx", "mjs", "cjs": self = .javascript
        case "json", "jsonc": self = .json
        case "kt", "kts": self = .kotlin
        case "less": self = .less
        case "lua": self = .lua
        case "md", "markdown": self = .markdown
        case "pl", "pm", "perl": self = .perl
        case "php": self = .php
        case "py", "pyw": self = .python
        case "rb", "rake", "gemspec": self = .ruby
        case "rs": self = .rust
        case "scss", "sass": self = .scss
        case "sh", "bash", "zsh": self = .shell
        case "sql": self = .sql
        case "swift": self = .swift
        case "toml": self = .toml
        case "ts", "tsx": self = .typescript
        case "xml", "plist", "xib", "storyboard", "svg": self = .xml
        case "yaml", "yml": self = .yaml
        default: self = .plainText
        }
    }

    var iconName: String {
        switch self {
        case .c: "c.circle"
        case .cpp: "plus.forwardslash.minus"
        case .css: "paintbrush"
        case .dart: "bird"
        case .go: "bolt.horizontal"
        case .html: "globe"
        case .ini: "gearshape"
        case .java: "cup.and.saucer"
        case .javascript: "curlybraces"
        case .json: "curlybraces.square"
        case .kotlin: "k.square"
        case .less: "paintbrush.pointed"
        case .lua: "moon.stars"
        case .markdown: "doc.richtext"
        case .perl: "p.circle"
        case .php: "p.square"
        case .python: "chevron.left.forwardslash.chevron.right"
        case .ruby: "diamond"
        case .rust: "gearshape.2"
        case .scss: "paintbrush.pointed"
        case .shell: "terminal"
        case .sql: "cylinder.split.1x2"
        case .swift: "swift"
        case .toml: "doc.plaintext"
        case .typescript: "t.square"
        case .xml: "chevron.left.forwardslash.chevron.right"
        case .yaml: "list.bullet.rectangle"
        case .plainText: "doc.text"
        }
    }

    /// Compact language mark used where SF Symbols do not provide an accurate
    /// language glyph. Keeps the file tree recognizable without brand assets.
    var iconMonogram: String? {
        switch self {
        case .swift, .shell, .markdown, .plainText: nil
        case .c: "C"
        case .cpp: "C++"
        case .css: "CSS"
        case .dart: "D"
        case .go: "GO"
        case .html: "HT"
        case .ini: "INI"
        case .java: "JV"
        case .javascript: "JS"
        case .json: "{}"
        case .kotlin: "KT"
        case .less: "LE"
        case .lua: "LU"
        case .perl: "PL"
        case .php: "PHP"
        case .python: "PY"
        case .ruby: "RB"
        case .rust: "RS"
        case .scss: "SC"
        case .sql: "SQL"
        case .toml: "TM"
        case .typescript: "TS"
        case .xml: "XM"
        case .yaml: "YM"
        }
    }

    var isRunnable: Bool {
        switch self {
        case .c, .cpp, .go, .java, .javascript, .lua, .perl, .php, .python, .ruby, .rust, .shell, .swift, .typescript:
            true
        default:
            false
        }
    }

    /// Whether indentation-based code folding is meaningful. Disabled for prose
    /// (Markdown, plain text) where leading whitespace is layout — not nesting —
    /// so chevrons would appear on arbitrary lines (ASCII diagrams, lists, …).
    var supportsFolding: Bool {
        switch self {
        case .markdown, .plainText: false
        default: true
        }
    }

    /// Whether a built-in external formatter is wired up for this language (the
    /// same set `FormatterService` knows how to drive). Gates the editor's
    /// "Format Document" context-menu item and ⇧⌥F shortcut.
    var supportsFormatting: Bool {
        switch self {
        case .c, .cpp, .swift, .go, .rust, .python,
             .javascript, .typescript, .css, .json, .html, .markdown, .yaml:
            true
        default:
            false
        }
    }

    var preferredExtension: String {
        switch self {
        case .c: "c"
        case .cpp: "cpp"
        case .dart: "dart"
        case .go: "go"
        case .ini: "ini"
        case .java: "java"
        case .javascript: "js"
        case .kotlin: "kt"
        case .less: "less"
        case .lua: "lua"
        case .perl: "pl"
        case .python: "py"
        case .ruby: "rb"
        case .rust: "rs"
        case .scss: "scss"
        case .shell: "sh"
        case .sql: "sql"
        case .swift: "swift"
        case .toml: "toml"
        case .typescript: "ts"
        case .css: "css"
        case .html: "html"
        case .json: "json"
        case .markdown: "md"
        case .php: "php"
        case .yaml: "yml"
        case .xml: "xml"
        case .plainText: "txt"
        }
    }

    var completionWords: [String] {
        switch self {
        case .c:
            ["#include", "#define", "printf", "scanf", "malloc", "free", "sizeof", "int", "char", "double", "float", "void", "struct", "return", "for", "while", "if", "else"]
        case .cpp:
            ["#include", "std::cout", "std::cin", "std::vector", "std::string", "namespace", "class", "template", "typename", "auto", "const", "return", "for", "while", "if", "else"]
        case .swift:
            ["import", "struct", "class", "enum", "extension", "func", "var", "let", "guard", "if", "else", "switch", "case", "return", "async", "await"]
        case .javascript, .typescript:
            ["import", "export", "const", "let", "function", "async", "await", "return", "class", "interface", "type", "if", "else", "for", "while"]
        case .python:
            ["import", "from", "def", "class", "self", "return", "if", "elif", "else", "for", "while", "with", "try", "except", "print", "len", "range", "enumerate", "zip", "open", "isinstance", "True", "False", "None"]
        case .go:
            ["package", "import", "func", "return", "struct", "interface", "defer", "go", "range", "if", "else", "for"]
        case .rust:
            ["use", "fn", "let", "mut", "pub", "impl", "trait", "struct", "enum", "match", "return", "async", "await"]
        case .shell:
            ["#!/usr/bin/env bash", "set -euo pipefail", "if", "then", "else", "fi", "for", "do", "done", "case", "esac"]
        case .html, .xml:
            ["html", "head", "body", "script", "style", "div", "span", "section", "article", "link", "meta"]
        case .css, .scss, .less:
            ["display", "grid", "flex", "align-items", "justify-content", "color", "background", "font-size", "padding", "margin", "@media", "@mixin", "@include"]
        case .java:
            ["import", "package", "public", "private", "protected", "class", "interface", "extends", "implements", "static", "final", "void", "return", "new", "if", "else", "for", "while", "try", "catch"]
        case .kotlin:
            ["import", "package", "fun", "val", "var", "class", "object", "interface", "data", "sealed", "when", "return", "if", "else", "for", "while", "suspend", "override"]
        case .ruby:
            ["require", "def", "end", "class", "module", "if", "elsif", "else", "unless", "do", "return", "yield", "attr_accessor", "puts"]
        case .lua:
            ["local", "function", "end", "if", "then", "else", "elseif", "for", "while", "do", "return", "require", "nil", "true", "false"]
        case .sql:
            ["SELECT", "FROM", "WHERE", "INSERT", "INTO", "VALUES", "UPDATE", "SET", "DELETE", "CREATE", "TABLE", "ALTER", "DROP", "JOIN", "INNER", "LEFT", "GROUP BY", "ORDER BY", "LIMIT"]
        case .perl:
            ["use", "my", "our", "sub", "if", "elsif", "else", "unless", "foreach", "while", "return", "print"]
        case .php:
            ["<?php", "echo", "function", "class", "public", "private", "protected", "static", "return", "namespace", "use", "if", "else", "elseif", "foreach", "while", "$this"]
        case .dart:
            ["import", "class", "extends", "implements", "void", "final", "const", "var", "late", "async", "await", "return", "if", "else", "for", "while", "Widget", "build", "override"]
        case .toml:
            ["true", "false"]
        case .ini:
            ["true", "false", "yes", "no"]
        case .json, .yaml, .markdown, .plainText:
            []
        }
    }
}
