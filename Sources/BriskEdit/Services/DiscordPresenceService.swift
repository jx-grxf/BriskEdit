import Darwin
import Foundation

// MARK: - Public model

/// One snapshot of what BriskEdit wants to show on the user's Discord profile.
/// Built from the frontmost workspace (see `make`) and handed to the controller,
/// which throttles and forwards it to the local Discord client over IPC.
struct DiscordActivity: Equatable, Sendable {
    /// First line on the Discord card — the file the user is editing.
    var details: String?
    /// Second line — the workspace/folder.
    var state: String?
    /// Large art-asset key (the BriskEdit logo, uploaded to the Discord app).
    var largeImageKey: String
    var largeImageText: String
    /// Small art-asset key overlaid on the large one (the language logo).
    var smallImageKey: String?
    var smallImageText: String?
    /// Unix epoch seconds; when set, Discord shows a live "elapsed" timer.
    var startTimestamp: Int?

    /// The `activity` object Discord's SET_ACTIVITY expects.
    func activityDictionary() -> [String: Any] {
        var assets: [String: Any] = ["large_image": largeImageKey]
        if let text = Self.validText(largeImageText) { assets["large_text"] = text }
        if let smallImageKey { assets["small_image"] = smallImageKey }
        if let text = Self.validText(smallImageText) { assets["small_text"] = text }

        var activity: [String: Any] = ["assets": assets]
        if let text = Self.validText(details) { activity["details"] = text }
        if let text = Self.validText(state) { activity["state"] = text }
        if let startTimestamp { activity["timestamps"] = ["start": startTimestamp] }
        return activity
    }

    /// Discord requires every presence **text** field to be 2–128 characters and
    /// rejects the *entire* activity otherwise (code 4000) — a one-letter language
    /// name like "C" or an over-long filename would silently kill the card. Trim
    /// to 128 and drop anything under 2. (Asset *keys* aren't subject to this and
    /// are passed through untouched.)
    private static func validText(_ value: String?) -> String? {
        guard let value else { return nil }
        let clamped = String(value.prefix(128))
        return clamped.count >= 2 ? clamped : nil
    }
}

// MARK: - Controller (main-actor facing API)

/// Process-global coordinator the rest of the app talks to. It debounces updates
/// (Discord rate-limits rich-presence writes) and owns the IPC connection's
/// lifecycle. Disabled by default and a complete no-op until a real Discord
/// application id is set and the feature is switched on in Settings.
@MainActor
final class DiscordPresenceController {
    static let shared = DiscordPresenceController()

    /// One-time project setup: create a Discord Application at
    /// https://discord.com/developers/applications, copy its *Application ID*
    /// here, and upload the art assets (a `briskedit` logo plus one image per
    /// `SourceLanguage.discordAssetKey`) under Rich Presence ▸ Art Assets.
    /// The id is public — it ships in the binary, exactly like vscord does.
    static let clientID = "1512848171825631242"

    /// Seconds the app has been open — used for the "elapsed" timer so it counts
    /// the session rather than resetting on every file switch.
    let sessionStart = Int(Date().timeIntervalSince1970)

    private let connection = DiscordIPCConnection()
    private var enabled = false
    private var latest: DiscordActivity?
    private var sendTask: Task<Void, Never>?
    private var lastSentAt = Date.distantPast

    /// Minimum gap between writes. Discord drops presence updates that arrive
    /// faster than ~5 per 20 s; 2 s keeps us comfortably under that.
    private let minInterval: TimeInterval = 2

    private var isConfigured: Bool { Self.clientID != "REPLACE_WITH_BRISKEDIT_DISCORD_APPLICATION_ID" }

    private init() {}

    /// Turns presence on/off (driven by the Settings toggle).
    func configure(enabled: Bool) {
        guard enabled != self.enabled else { return }
        self.enabled = enabled
        guard isConfigured else { return }
        if enabled {
            scheduleSend()
        } else {
            sendTask?.cancel()
            Task { await connection.clearAndDisconnect() }
        }
    }

    /// Latest desired presence from the frontmost window. Stored even while
    /// disabled so flipping the toggle on immediately shows the current file.
    func update(_ activity: DiscordActivity) {
        guard activity != latest else { return }
        latest = activity
        guard enabled, isConfigured else { return }
        scheduleSend()
    }

    func shutdown() {
        sendTask?.cancel()
        Task { await connection.clearAndDisconnect() }
    }

    private func scheduleSend() {
        // Never push an empty activity here — that would *clear* the card. The
        // only deliberate clear goes through `clearAndDisconnect` on disable/quit.
        guard let activity = latest else { return }
        sendTask?.cancel()
        let wait = max(0, minInterval - Date().timeIntervalSince(lastSentAt))
        sendTask = Task { [weak self] in
            if wait > 0 { try? await Task.sleep(for: .seconds(wait)) }
            guard let self, !Task.isCancelled else { return }
            self.lastSentAt = Date()
            await self.connection.setActivity(activity, clientID: Self.clientID)
        }
    }
}

// MARK: - IPC connection (off the main actor)

/// Speaks Discord's local IPC protocol over a Unix-domain socket: a tiny binary
/// framing (`UInt32` opcode + `UInt32` little-endian length + JSON payload) with
/// a `client_id` handshake, then `SET_ACTIVITY` frames. No SDK required.
private actor DiscordIPCConnection {
    private var fd: Int32 = -1
    private let pid = ProcessInfo.processInfo.processIdentifier

    func setActivity(_ activity: DiscordActivity?, clientID: String) {
        if fd < 0, !connect(clientID: clientID) { return }
        let frame = encode(opcode: 1, payload: setActivityPayload(activity))
        if writeAll(frame) { return }
        // Discord likely restarted — reconnect once and resend.
        disconnect()
        if connect(clientID: clientID) { _ = writeAll(frame) }
    }

    func clearAndDisconnect() {
        if fd >= 0 {
            _ = writeAll(encode(opcode: 1, payload: setActivityPayload(nil)))
            disconnect()
        }
    }

    // MARK: Protocol

    private func setActivityPayload(_ activity: DiscordActivity?) -> Data {
        let args: [String: Any] = [
            "pid": Int(pid),
            "activity": activity?.activityDictionary() ?? NSNull(),
        ]
        let command: [String: Any] = [
            "cmd": "SET_ACTIVITY",
            "args": args,
            "nonce": UUID().uuidString,
        ]
        return (try? JSONSerialization.data(withJSONObject: command)) ?? Data()
    }

    private func connect(clientID: String) -> Bool {
        for path in Self.candidateSocketPaths() {
            guard let socket = openSocket(path: path) else { continue }
            let handshake = (try? JSONSerialization.data(withJSONObject: ["v": 1, "client_id": clientID])) ?? Data()
            fd = socket
            guard writeAll(encode(opcode: 0, payload: handshake)),
                  let frame = readFrame(), frame.opcode == 1 else {
                disconnect()
                continue
            }
            return true
        }
        return false
    }

    private func disconnect() {
        if fd >= 0 { close(fd) }
        fd = -1
    }

    /// Discord exposes `discord-ipc-0` … `discord-ipc-9` in the system temp dir.
    private static func candidateSocketPaths() -> [String] {
        let env = ProcessInfo.processInfo.environment
        let bases = ["XDG_RUNTIME_DIR", "TMPDIR", "TMP", "TEMP"]
            .compactMap { env[$0] }
            .map { $0.hasSuffix("/") ? String($0.dropLast()) : $0 }
        let dirs = (bases.isEmpty ? ["/tmp"] : bases)
        var paths: [String] = []
        for dir in dirs {
            for index in 0..<10 { paths.append("\(dir)/discord-ipc-\(index)") }
        }
        return paths
    }

    // MARK: Framing

    private func encode(opcode: UInt32, payload: Data) -> Data {
        var data = Data(capacity: 8 + payload.count)
        var op = opcode.littleEndian
        var len = UInt32(payload.count).littleEndian
        withUnsafeBytes(of: &op) { data.append(contentsOf: $0) }
        withUnsafeBytes(of: &len) { data.append(contentsOf: $0) }
        data.append(payload)
        return data
    }

    private func readFrame() -> (opcode: UInt32, payload: Data)? {
        guard fd >= 0, let header = readExactly(8) else { return nil }
        let opcode = header.withUnsafeBytes { $0.loadUnaligned(fromByteOffset: 0, as: UInt32.self).littleEndian }
        let length = header.withUnsafeBytes { $0.loadUnaligned(fromByteOffset: 4, as: UInt32.self).littleEndian }
        guard length <= 1024 * 1024 else { return nil }
        guard let payload = readExactly(Int(length)) else { return nil }
        return (opcode, payload)
    }

    // MARK: POSIX socket I/O

    private func openSocket(path: String) -> Int32? {
        let socketFD = socket(AF_UNIX, SOCK_STREAM, 0)
        guard socketFD >= 0 else { return nil }

        var addr = sockaddr_un()
        addr.sun_family = sa_family_t(AF_UNIX)
        let capacity = MemoryLayout.size(ofValue: addr.sun_path)
        let copied = path.withCString { cString -> Bool in
            guard strlen(cString) < capacity else { return false }
            withUnsafeMutablePointer(to: &addr.sun_path) {
                $0.withMemoryRebound(to: CChar.self, capacity: capacity) { dst in
                    _ = strcpy(dst, cString)
                }
            }
            return true
        }
        guard copied else { close(socketFD); return nil }

        let size = socklen_t(MemoryLayout<sockaddr_un>.size)
        let result = withUnsafePointer(to: &addr) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { Darwin.connect(socketFD, $0, size) }
        }
        guard result == 0 else { close(socketFD); return nil }

        // Bound the blocking reads/writes so a hung or unresponsive Discord client
        // can never wedge this connection actor — a timed-out read just fails the
        // frame and we reconnect on the next update.
        var timeout = timeval(tv_sec: 2, tv_usec: 0)
        let optionSize = socklen_t(MemoryLayout<timeval>.size)
        setsockopt(socketFD, SOL_SOCKET, SO_RCVTIMEO, &timeout, optionSize)
        setsockopt(socketFD, SOL_SOCKET, SO_SNDTIMEO, &timeout, optionSize)
        return socketFD
    }

    private func writeAll(_ data: Data) -> Bool {
        guard fd >= 0 else { return false }
        return data.withUnsafeBytes { raw -> Bool in
            guard var pointer = raw.baseAddress else { return true }
            var remaining = raw.count
            while remaining > 0 {
                let written = Darwin.write(fd, pointer, remaining)
                if written <= 0 { return false }
                pointer = pointer.advanced(by: written)
                remaining -= written
            }
            return true
        }
    }

    private func readExactly(_ count: Int) -> Data? {
        if count == 0 { return Data() }
        guard fd >= 0 else { return nil }
        var buffer = [UInt8](repeating: 0, count: count)
        var total = 0
        while total < count {
            let read = buffer.withUnsafeMutableBytes {
                Darwin.read(fd, $0.baseAddress!.advanced(by: total), count - total)
            }
            if read <= 0 { return nil }
            total += read
        }
        return Data(buffer)
    }
}

// MARK: - Language → Discord art-asset key

extension SourceLanguage {
    /// Key of the uploaded art asset for this language's small icon. Lowercased
    /// and alphanumeric to satisfy Discord's asset-key rules.
    var discordAssetKey: String {
        switch self {
        case .c: "c"
        case .cpp: "cpp"
        case .css: "css"
        case .dart: "dart"
        case .go: "go"
        case .html: "html"
        case .ini: "ini"
        case .java: "java"
        case .javascript: "javascript"
        case .json: "json"
        case .kotlin: "kotlin"
        case .less: "less"
        case .lua: "lua"
        case .markdown: "markdown"
        case .perl: "perl"
        case .php: "php"
        case .python: "python"
        case .ruby: "ruby"
        case .rust: "rust"
        case .scss: "scss"
        case .shell: "shell"
        case .sql: "sql"
        case .swift: "swift"
        case .toml: "toml"
        case .typescript: "typescript"
        case .xml: "xml"
        case .yaml: "yaml"
        case .plainText: "text"
        }
    }
}

// MARK: - Building the activity from a workspace

extension DiscordActivity {
    /// Snapshot of the given workspace, honoring the user's privacy toggles.
    @MainActor
    static func make(workspace: WorkspaceModel, preferences: Preferences) -> DiscordActivity {
        var details: String?
        var smallKey: String?
        var smallText: String?

        if let document = workspace.activeTab?.document {
            let language = document.language
            details = preferences.discordShowFileName
                ? "Editing \(document.displayName)"
                : "Editing a \(language.rawValue) file"
            smallKey = language.discordAssetKey
            smallText = language.rawValue
        } else {
            details = "Idle"
        }

        var state: String?
        if preferences.discordShowWorkspace, let root = workspace.rootURL {
            state = "Workspace: \(root.lastPathComponent)"
        }

        return DiscordActivity(
            details: details,
            state: state,
            largeImageKey: "briskedit",
            largeImageText: "BriskEdit",
            smallImageKey: smallKey,
            smallImageText: smallText,
            startTimestamp: preferences.discordShowElapsed ? DiscordPresenceController.shared.sessionStart : nil
        )
    }
}
