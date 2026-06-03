import Foundation

/// Delivers live LSP `publishDiagnostics` to whichever editor owns a document
/// URI. The editor coordinator registers a handler for its file; the LSP actor
/// pushes findings here on the main actor.
@MainActor
final class LSPDiagnosticsBus {
    static let shared = LSPDiagnosticsBus()
    private var handlers: [String: ([Diagnostic]) -> Void] = [:]

    func setHandler(uri: String, _ handler: @escaping ([Diagnostic]) -> Void) {
        handlers[uri] = handler
    }

    func removeHandler(uri: String) {
        handlers[uri] = nil
    }

    func deliver(uri: String, diagnostics: [Diagnostic]) {
        handlers[uri]?(diagnostics)
    }
}

/// Synchronously-reachable registry of the live language-server processes so the
/// app can terminate them on quit. Without this, clangd/sourcekit-lsp/… would
/// outlive the app as orphaned processes — exactly the bloat BriskEdit avoids.
final class LSPProcessRegistry: @unchecked Sendable {
    static let shared = LSPProcessRegistry()
    private let lock = NSLock()
    private var processes: [ObjectIdentifier: Process] = [:]

    func register(_ process: Process) {
        lock.lock(); defer { lock.unlock() }
        processes[ObjectIdentifier(process)] = process
    }

    func unregister(_ process: Process) {
        lock.lock(); defer { lock.unlock() }
        processes[ObjectIdentifier(process)] = nil
    }

    /// Terminates every tracked server immediately. Safe to call from
    /// `applicationWillTerminate` — `Process.terminate()` is synchronous.
    func terminateAll() {
        lock.lock()
        let running = Array(processes.values)
        processes.removeAll()
        lock.unlock()
        for process in running where process.isRunning {
            process.terminate()
        }
    }
}

/// A semantic completion from a language server, carrying enough to render a
/// rich popup row (label, signature/type detail, kind badge).
struct LSPCompletion: Sendable, Equatable {
    let label: String
    let detail: String?
    let kind: Int
}

/// A symbol from `textDocument/documentSymbol` for the outline. 1-based
/// line/column; children mirror the LSP hierarchy.
struct LSPSymbol: Sendable, Hashable, Identifiable {
    let id = UUID()
    let name: String
    let detail: String?
    let kind: Int
    let line: Int
    let column: Int
    var children: [LSPSymbol]
}

/// A resolved source location from go-to-definition. 1-based line/column.
struct LSPLocation: Sendable, Equatable {
    let uri: String
    let line: Int
    let column: Int
}

struct LSPToolStatus: Sendable, Equatable {
    enum State: Sendable, Equatable {
        case available
        case missing
        case unsupported
    }

    let state: State
    let serverName: String
    let detail: String

    static let unsupported = LSPToolStatus(
        state: .unsupported,
        serverName: "Off",
        detail: "No language server for this file type"
    )
}

/// Minimal multi-server LSP client. Speaks JSON-RPC over a server's stdio to
/// provide semantic completion and live diagnostics, using the language servers
/// the developer already has installed (clangd via Xcode, sourcekit-lsp, gopls,
/// pyright, rust-analyzer, typescript-language-server). Everything is best
/// effort: a missing or misbehaving server just yields no results and the editor
/// falls back to keyword/buffer completion.
actor LSPService {
    static let shared = LSPService()

    struct ServerConfig {
        let id: String
        let executable: String        // direct path, or "zsh" wrapper for PATH lookup
        let arguments: [String]
        let probe: String?            // command to verify availability, nil = always present
        let languageId: String

        var displayName: String {
            switch id {
            case "sourcekit": "sourcekit-lsp"
            case "tsserver": "typescript-language-server"
            default: id
            }
        }
    }

    /// Resolves the server launch for a language, or nil if BriskEdit drives no
    /// server for it. Non-Xcode servers launch through a login shell so a GUI
    /// process still sees Homebrew/`PATH`.
    static func config(for language: SourceLanguage) -> ServerConfig? {
        func shell(_ command: String) -> (String, [String]) {
            ("/bin/zsh", ["-lc", "exec \(command)"])
        }
        switch language {
        case .c, .cpp:
            return ServerConfig(id: "clangd", executable: "/usr/bin/xcrun",
                                arguments: ["clangd", "--log=error", "--background-index=false", "--limit-results=80"],
                                probe: nil, languageId: language == .cpp ? "cpp" : "c")
        case .swift:
            return ServerConfig(id: "sourcekit", executable: "/usr/bin/xcrun",
                                arguments: ["sourcekit-lsp"], probe: nil, languageId: "swift")
        case .go:
            let (exe, args) = shell("gopls")
            return ServerConfig(id: "gopls", executable: exe, arguments: args, probe: "gopls", languageId: "go")
        case .python:
            let (exe, args) = shell("pyright-langserver --stdio")
            return ServerConfig(id: "pyright", executable: exe, arguments: args, probe: "pyright-langserver", languageId: "python")
        case .rust:
            let (exe, args) = shell("rust-analyzer")
            return ServerConfig(id: "rust-analyzer", executable: exe, arguments: args, probe: "rust-analyzer", languageId: "rust")
        case .javascript, .typescript:
            let (exe, args) = shell("typescript-language-server --stdio")
            return ServerConfig(id: "tsserver", executable: exe, arguments: args, probe: "typescript-language-server",
                                languageId: language == .typescript ? "typescript" : "javascript")
        default:
            return nil
        }
    }

    static func toolStatus(for language: SourceLanguage) async -> LSPToolStatus {
        guard let config = config(for: language) else { return .unsupported }
        let path = await Task.detached(priority: .utility) {
            resolveExecutablePath(for: config)
        }.value
        if let path {
            return LSPToolStatus(state: .available, serverName: config.displayName, detail: path)
        }
        return LSPToolStatus(
            state: .missing,
            serverName: config.displayName,
            detail: "\(config.displayName) was not found on PATH"
        )
    }

    private struct ServerKey: Hashable {
        let id: String
        let rootURI: String?
    }

    private var servers: [ServerKey: Server] = [:]

    /// Returns semantic completions for the position, syncing the buffer first.
    func completions(language: SourceLanguage, uri: String, text: String, line: Int, character: Int, root: String?) async -> [LSPCompletion] {
        guard let config = Self.config(for: language) else { return [] }
        guard let server = await ensureServer(config, root: root) else { return [] }
        await server.sync(uri: uri, languageId: config.languageId, text: text)
        let params: [String: Any] = [
            "textDocument": ["uri": uri],
            "position": ["line": line, "character": character],
            "context": ["triggerKind": 1]
        ]
        guard let data = await server.request(method: "textDocument/completion", params: params),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return [] }
        return Self.parseCompletions(json["result"])
    }

    /// Symbol tree for the outline (`textDocument/documentSymbol`).
    func documentSymbols(language: SourceLanguage, uri: String, text: String, root: String?) async -> [LSPSymbol] {
        guard let config = Self.config(for: language), let server = await ensureServer(config, root: root) else { return [] }
        await server.sync(uri: uri, languageId: config.languageId, text: text)
        guard let data = await server.request(method: "textDocument/documentSymbol", params: ["textDocument": ["uri": uri]]),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return [] }
        return Self.parseSymbols(json["result"])
    }

    /// Resolves the definition of the symbol at a position (`textDocument/definition`).
    func definition(language: SourceLanguage, uri: String, text: String, line: Int, character: Int, root: String?) async -> LSPLocation? {
        guard let config = Self.config(for: language), let server = await ensureServer(config, root: root) else { return nil }
        await server.sync(uri: uri, languageId: config.languageId, text: text)
        let params: [String: Any] = ["textDocument": ["uri": uri], "position": ["line": line, "character": character]]
        guard let data = await server.request(method: "textDocument/definition", params: params),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        return Self.parseLocation(json["result"])
    }

    /// Hover documentation/type for the symbol at a position (`textDocument/hover`).
    func hover(language: SourceLanguage, uri: String, text: String, line: Int, character: Int, root: String?) async -> String? {
        guard let config = Self.config(for: language), let server = await ensureServer(config, root: root) else { return nil }
        await server.sync(uri: uri, languageId: config.languageId, text: text)
        let params: [String: Any] = ["textDocument": ["uri": uri], "position": ["line": line, "character": character]]
        guard let data = await server.request(method: "textDocument/hover", params: params),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        return Self.parseHover(json["result"])
    }

    /// Opens (or refreshes) a document so the server starts emitting diagnostics
    /// without waiting for a completion request.
    func openDocument(language: SourceLanguage, uri: String, text: String, root: String?) async {
        guard let config = Self.config(for: language) else { return }
        guard let server = await ensureServer(config, root: root) else { return }
        await server.sync(uri: uri, languageId: config.languageId, text: text)
    }

    /// Tells the server a document was closed (tab closed) so it drops the
    /// buffer and stops emitting diagnostics for it.
    func didClose(language: SourceLanguage, uri: String) async {
        guard let config = Self.config(for: language) else { return }
        for (key, server) in servers where key.id == config.id {
            await server.close(uri: uri)
        }
    }

    /// Shuts every running server down (LSP `shutdown`/`exit`, then terminate).
    /// Called on app quit.
    func shutdownAll() async {
        let running = Array(servers.values)
        servers.removeAll()
        for server in running {
            await server.shutdown()
        }
    }

    private func ensureServer(_ config: ServerConfig, root: String?) async -> Server? {
        let key = ServerKey(id: config.id, rootURI: Self.rootURI(for: root))
        if let existing = servers[key] {
            return await existing.initialized ? existing : nil
        }
        let server = Server(config: config)
        servers[key] = server
        guard await server.start(root: root) else {
            await server.shutdown()
            servers[key] = nil
            return nil
        }
        return server
    }

    private static func rootURI(for root: String?) -> String? {
        root.map { URL(fileURLWithPath: $0).absoluteString }
    }

    // MARK: - Completion parsing

    private static func parseCompletions(_ result: Any?) -> [LSPCompletion] {
        let items: [[String: Any]]
        if let dict = result as? [String: Any], let list = dict["items"] as? [[String: Any]] {
            items = list
        } else if let list = result as? [[String: Any]] {
            items = list
        } else {
            return []
        }
        let ranked = items.sorted { lhs, rhs in
            let l = (lhs["sortText"] as? String) ?? (lhs["label"] as? String) ?? ""
            let r = (rhs["sortText"] as? String) ?? (rhs["label"] as? String) ?? ""
            return l < r
        }
        var seen = Set<String>()
        var completions: [LSPCompletion] = []
        for item in ranked {
            let raw = (item["insertText"] as? String) ?? (item["label"] as? String) ?? ""
            let symbol = raw.prefix { $0.isLetter || $0.isNumber || $0 == "_" || $0 == "#" }
            let token = symbol.isEmpty ? raw.trimmingCharacters(in: .whitespaces) : String(symbol)
            guard !token.isEmpty, seen.insert(token).inserted else { continue }
            // `detail` is clangd's signature/type; `labelDetails.detail` is its
            // newer home. Fall back across both.
            let detail = (item["detail"] as? String)
                ?? ((item["labelDetails"] as? [String: Any])?["detail"] as? String)
            let kind = (item["kind"] as? Int) ?? 1
            completions.append(LSPCompletion(label: token, detail: detail?.trimmingCharacters(in: .whitespaces), kind: kind))
        }
        return completions
    }

    private static func parseSymbols(_ result: Any?) -> [LSPSymbol] {
        guard let list = result as? [[String: Any]] else { return [] }
        return list.compactMap(parseSymbol)
    }

    private static func parseSymbol(_ dict: [String: Any]) -> LSPSymbol? {
        guard let name = dict["name"] as? String, !name.isEmpty else { return nil }
        let kind = dict["kind"] as? Int ?? 0
        let detail = (dict["detail"] as? String)?.trimmingCharacters(in: .whitespaces)
        // DocumentSymbol uses selectionRange/range; SymbolInformation nests it
        // under location.range.
        let range = (dict["selectionRange"] as? [String: Any])
            ?? (dict["range"] as? [String: Any])
            ?? ((dict["location"] as? [String: Any])?["range"] as? [String: Any])
        let start = range?["start"] as? [String: Any]
        let line = (start?["line"] as? Int ?? 0) + 1
        let column = (start?["character"] as? Int ?? 0) + 1
        let children = (dict["children"] as? [[String: Any]])?.compactMap(parseSymbol) ?? []
        return LSPSymbol(name: name, detail: detail?.isEmpty == true ? nil : detail, kind: kind, line: line, column: column, children: children)
    }

    private static func parseLocation(_ result: Any?) -> LSPLocation? {
        func from(_ dict: [String: Any]) -> LSPLocation? {
            let uri = (dict["uri"] as? String) ?? (dict["targetUri"] as? String)
            let range = (dict["range"] as? [String: Any])
                ?? (dict["targetSelectionRange"] as? [String: Any])
                ?? (dict["targetRange"] as? [String: Any])
            guard let uri, let start = range?["start"] as? [String: Any] else { return nil }
            return LSPLocation(uri: uri, line: (start["line"] as? Int ?? 0) + 1, column: (start["character"] as? Int ?? 0) + 1)
        }
        if let dict = result as? [String: Any] { return from(dict) }
        if let arr = result as? [[String: Any]], let first = arr.first { return from(first) }
        return nil
    }

    private static func parseHover(_ result: Any?) -> String? {
        guard let dict = result as? [String: Any], let contents = dict["contents"] else { return nil }
        func text(_ any: Any) -> String? {
            if let s = any as? String { return s }
            if let m = any as? [String: Any] { return m["value"] as? String }
            return nil
        }
        let raw: String?
        if let s = text(contents) {
            raw = s
        } else if let arr = contents as? [Any] {
            raw = arr.compactMap(text).joined(separator: "\n")
        } else {
            raw = nil
        }
        let trimmed = raw?.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed?.isEmpty == false ? trimmed : nil
    }

    private static func resolveExecutablePath(for config: ServerConfig) -> String? {
        let command: String
        if let probe = config.probe {
            command = "command -v \(probe)"
        } else if config.executable == "/usr/bin/xcrun", let tool = config.arguments.first {
            command = "/usr/bin/xcrun --find \(tool)"
        } else {
            command = "command -v \(config.executable)"
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/zsh")
        process.arguments = ["-lc", command]
        let stdout = Pipe()
        process.standardOutput = stdout
        process.standardError = FileHandle.nullDevice
        do { try process.run() } catch { return nil }
        let data = stdout.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else { return nil }
        let output = String(data: data, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return output?.isEmpty == false ? output : nil
    }
}

/// One language-server process and its JSON-RPC plumbing. An actor so its
/// mutable buffer/continuation state stays serialized.
private actor Server {
    private let config: LSPService.ServerConfig
    private var process: Process?
    private var stdin: FileHandle?
    private var outHandle: FileHandle?
    private var failed = false
    var initialized = false

    private var nextId = 1
    private var pending: [Int: CheckedContinuation<Data?, Never>] = [:]
    private var openVersions: [String: Int] = [:]
    private var lastText: [String: String] = [:]
    private var inbox = Data()

    init(config: LSPService.ServerConfig) {
        self.config = config
    }

    func start(root: String?) async -> Bool {
        if failed { return false }

        if let probe = config.probe, !Self.isAvailable(probe) {
            failed = true
            return false
        }

        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: config.executable)
        proc.arguments = config.arguments
        let inPipe = Pipe()
        let outPipe = Pipe()
        proc.standardInput = inPipe
        proc.standardOutput = outPipe
        proc.standardError = FileHandle.nullDevice

        outPipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard !data.isEmpty else { return }
            Task { await self?.ingest(data) }
        }

        do { try proc.run() } catch {
            failed = true
            return false
        }
        process = proc
        stdin = inPipe.fileHandleForWriting
        outHandle = outPipe.fileHandleForReading
        LSPProcessRegistry.shared.register(proc)

        let rootUri = root.map { URL(fileURLWithPath: $0).absoluteString }
        let initParams: [String: Any] = [
            "processId": NSNull(),
            "rootUri": rootUri ?? NSNull(),
            "capabilities": [
                "textDocument": [
                    "completion": ["completionItem": ["snippetSupport": false]],
                    "publishDiagnostics": ["relatedInformation": false]
                ]
            ]
        ]
        guard await request(method: "initialize", params: initParams) != nil else {
            failed = true
            await shutdown()
            return false
        }
        notify(method: "initialized", params: [:])
        initialized = true
        return true
    }

    func sync(uri: String, languageId: String, text: String) {
        if openVersions[uri] == nil {
            openVersions[uri] = 1
            lastText[uri] = text
            notify(method: "textDocument/didOpen", params: [
                "textDocument": ["uri": uri, "languageId": languageId, "version": 1, "text": text]
            ])
        } else if lastText[uri] != text {
            let version = (openVersions[uri] ?? 1) + 1
            openVersions[uri] = version
            lastText[uri] = text
            notify(method: "textDocument/didChange", params: [
                "textDocument": ["uri": uri, "version": version],
                "contentChanges": [["text": text]]
            ])
        }
    }

    /// Sends `textDocument/didClose` and forgets the buffer so the server stops
    /// tracking/diagnosing it. No-op if the document was never opened.
    func close(uri: String) {
        guard openVersions[uri] != nil else { return }
        openVersions[uri] = nil
        lastText[uri] = nil
        notify(method: "textDocument/didClose", params: [
            "textDocument": ["uri": uri]
        ])
    }

    /// Gracefully stops the server: LSP `shutdown` + `exit`, drop the read
    /// handler, terminate the process. Resilient to a half-started server.
    func shutdown() async {
        guard let process else { return }
        if initialized {
            _ = await request(method: "shutdown", params: [:])
            notify(method: "exit", params: [:])
        }
        outHandle?.readabilityHandler = nil
        if process.isRunning { process.terminate() }
        LSPProcessRegistry.shared.unregister(process)
        self.process = nil
        stdin = nil
        outHandle = nil
        initialized = false
        // Fail any in-flight requests so their continuations don't leak.
        for (_, continuation) in pending { continuation.resume(returning: nil) }
        pending.removeAll()
    }

    // MARK: - JSON-RPC

    func request(method: String, params: [String: Any]) async -> Data? {
        let id = nextId
        nextId += 1
        let message: [String: Any] = ["jsonrpc": "2.0", "id": id, "method": method, "params": params]
        return await withCheckedContinuation { (continuation: CheckedContinuation<Data?, Never>) in
            pending[id] = continuation
            guard send(message: message) else {
                if let continuation = pending.removeValue(forKey: id) {
                    continuation.resume(returning: nil)
                }
                return
            }
            Task {
                try? await Task.sleep(for: .seconds(5))
                await self.timeout(id: id)
            }
        }
    }

    private func timeout(id: Int) {
        if let continuation = pending.removeValue(forKey: id) {
            continuation.resume(returning: nil)
        }
    }

    private func notify(method: String, params: [String: Any]) {
        send(message: ["jsonrpc": "2.0", "method": method, "params": params])
    }

    @discardableResult
    private func send(message: [String: Any]) -> Bool {
        guard let stdin, let body = try? JSONSerialization.data(withJSONObject: message) else { return false }
        var frame = Data("Content-Length: \(body.count)\r\n\r\n".utf8)
        frame.append(body)
        do {
            try stdin.write(contentsOf: frame)
            return true
        } catch {
            return false
        }
    }

    private func ingest(_ data: Data) {
        inbox.append(data)
        while let body = extractMessage() {
            guard let json = try? JSONSerialization.jsonObject(with: body) as? [String: Any] else { continue }
            if let id = json["id"] as? Int, let continuation = pending.removeValue(forKey: id) {
                continuation.resume(returning: body)
            } else if json["method"] as? String == "textDocument/publishDiagnostics" {
                handlePublishDiagnostics(json["params"])
            }
        }
    }

    private func handlePublishDiagnostics(_ params: Any?) {
        guard let params = params as? [String: Any],
              let uri = params["uri"] as? String,
              let raw = params["diagnostics"] as? [[String: Any]] else { return }
        let diagnostics = raw.compactMap(Self.parseDiagnostic)
        Task { @MainActor in
            LSPDiagnosticsBus.shared.deliver(uri: uri, diagnostics: diagnostics)
        }
    }

    private static func parseDiagnostic(_ raw: [String: Any]) -> Diagnostic? {
        guard let range = raw["range"] as? [String: Any],
              let start = range["start"] as? [String: Any],
              let line = start["line"] as? Int,
              let character = start["character"] as? Int else { return nil }
        let severityCode = raw["severity"] as? Int ?? 1
        let severity: Diagnostic.Severity = switch severityCode {
        case 1: .error
        case 2: .warning
        default: .note
        }
        let message = (raw["message"] as? String) ?? ""
        return Diagnostic(line: line + 1, column: character + 1, severity: severity, message: message)
    }

    private func extractMessage() -> Data? {
        let separator = Data("\r\n\r\n".utf8)
        guard let headerEnd = inbox.range(of: separator) else { return nil }
        let header = String(decoding: inbox[inbox.startIndex..<headerEnd.lowerBound], as: UTF8.self)
        var length = 0
        for line in header.split(separator: "\r\n") where line.lowercased().hasPrefix("content-length:") {
            length = Int(line.dropFirst("content-length:".count).trimmingCharacters(in: .whitespaces)) ?? 0
        }
        let bodyStart = headerEnd.upperBound
        guard length > 0, inbox.distance(from: bodyStart, to: inbox.endIndex) >= length else { return nil }
        let bodyEnd = inbox.index(bodyStart, offsetBy: length)
        let body = inbox[bodyStart..<bodyEnd]
        inbox.removeSubrange(inbox.startIndex..<bodyEnd)
        return Data(body)
    }

    private static func isAvailable(_ executable: String) -> Bool {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/zsh")
        process.arguments = ["-lc", "command -v \(executable)"]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        do { try process.run() } catch { return false }
        process.waitUntilExit()
        return process.terminationStatus == 0
    }
}
