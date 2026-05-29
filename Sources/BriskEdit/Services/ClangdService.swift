import Foundation

/// Minimal LSP client that talks to `clangd` (shipped with the Xcode toolchain)
/// over stdin/stdout to provide semantic C/C++ completions. Everything is best
/// effort: if clangd is missing or misbehaves the service simply returns no
/// results and the editor falls back to keyword/buffer completion.
actor ClangdService {
    static let shared = ClangdService()

    private var process: Process?
    private var stdin: FileHandle?
    private var started = false
    private var failed = false
    private var initialized = false

    private var nextId = 1
    private var pending: [Int: CheckedContinuation<Data?, Never>] = [:]
    private var openVersions: [String: Int] = [:]
    private var lastText: [String: String] = [:]
    private var inbox = Data()

    /// Returns completion labels for the position, syncing the buffer first.
    func completions(uri: String, languageId: String, text: String, line: Int, character: Int, root: String?) async -> [String] {
        guard await ensureStarted(root: root) else { return [] }
        sync(uri: uri, languageId: languageId, text: text)
        let params: [String: Any] = [
            "textDocument": ["uri": uri],
            "position": ["line": line, "character": character],
            "context": ["triggerKind": 1]
        ]
        guard let data = await request(method: "textDocument/completion", params: params),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return [] }
        return Self.parseCompletions(json["result"])
    }

    // MARK: - Lifecycle

    private func ensureStarted(root: String?) async -> Bool {
        if started { return initialized }
        if failed { return false }
        started = true

        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/usr/bin/xcrun")
        proc.arguments = ["clangd", "--log=error", "--background-index=false", "--limit-results=80"]
        let inPipe = Pipe()
        let outPipe = Pipe()
        proc.standardInput = inPipe
        proc.standardOutput = outPipe
        proc.standardError = FileHandle.nullDevice

        outPipe.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            guard !data.isEmpty else { return }
            Task { await ClangdService.shared.ingest(data) }
        }

        do {
            try proc.run()
        } catch {
            failed = true
            return false
        }
        process = proc
        stdin = inPipe.fileHandleForWriting

        let rootUri = root.map { "file://\($0)" }
        let initParams: [String: Any] = [
            "processId": NSNull(),
            "rootUri": rootUri ?? NSNull(),
            "capabilities": [
                "textDocument": [
                    "completion": [
                        "completionItem": ["snippetSupport": false]
                    ]
                ]
            ]
        ]
        guard await request(method: "initialize", params: initParams) != nil else {
            failed = true
            return false
        }
        notify(method: "initialized", params: [:])
        initialized = true
        return true
    }

    private func sync(uri: String, languageId: String, text: String) {
        if openVersions[uri] == nil {
            openVersions[uri] = 1
            lastText[uri] = text
            notify(method: "textDocument/didOpen", params: [
                "textDocument": [
                    "uri": uri,
                    "languageId": languageId,
                    "version": 1,
                    "text": text
                ]
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

    // MARK: - JSON-RPC

    private func request(method: String, params: [String: Any]) async -> Data? {
        let id = nextId
        nextId += 1
        send(message: ["jsonrpc": "2.0", "id": id, "method": method, "params": params])

        let result = await withCheckedContinuation { (continuation: CheckedContinuation<Data?, Never>) in
            pending[id] = continuation
            Task {
                try? await Task.sleep(for: .seconds(3))
                self.timeout(id: id)
            }
        }
        return result
    }

    private func timeout(id: Int) {
        if let continuation = pending.removeValue(forKey: id) {
            continuation.resume(returning: nil)
        }
    }

    private func notify(method: String, params: [String: Any]) {
        send(message: ["jsonrpc": "2.0", "method": method, "params": params])
    }

    private func send(message: [String: Any]) {
        guard let stdin, let body = try? JSONSerialization.data(withJSONObject: message) else { return }
        var frame = Data("Content-Length: \(body.count)\r\n\r\n".utf8)
        frame.append(body)
        try? stdin.write(contentsOf: frame)
    }

    private func ingest(_ data: Data) {
        inbox.append(data)
        while let body = extractMessage() {
            guard let json = try? JSONSerialization.jsonObject(with: body) as? [String: Any] else { continue }
            if let id = json["id"] as? Int, let continuation = pending.removeValue(forKey: id) {
                continuation.resume(returning: body)
            }
        }
    }

    /// Pulls one complete `Content-Length` framed message out of the inbox.
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

    private static func parseCompletions(_ result: Any?) -> [String] {
        let items: [[String: Any]]
        if let dict = result as? [String: Any], let list = dict["items"] as? [[String: Any]] {
            items = list
        } else if let list = result as? [[String: Any]] {
            items = list
        } else {
            return []
        }

        // Honor clangd's relevance ranking (sortText) so the best match is first.
        let ranked = items.sorted { lhs, rhs in
            let l = (lhs["sortText"] as? String) ?? (lhs["label"] as? String) ?? ""
            let r = (rhs["sortText"] as? String) ?? (rhs["label"] as? String) ?? ""
            return l < r
        }

        var seen = Set<String>()
        var labels: [String] = []
        for item in ranked {
            let raw = (item["insertText"] as? String) ?? (item["label"] as? String) ?? ""
            // Labels can carry signatures ("printf(…)"); keep just the symbol.
            let symbol = raw.prefix { $0.isLetter || $0.isNumber || $0 == "_" || $0 == "#" }
            let token = symbol.isEmpty ? raw.trimmingCharacters(in: .whitespaces) : String(symbol)
            guard !token.isEmpty, seen.insert(token).inserted else { continue }
            labels.append(token)
        }
        return labels
    }
}
