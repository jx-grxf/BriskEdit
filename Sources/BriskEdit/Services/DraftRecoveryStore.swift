import Darwin
import Foundation

struct RecoverableDraft: Codable, Identifiable, Sendable, Equatable {
    let id: UUID
    let filePath: String?
    let displayName: String
    let text: String
    let encodingRawValue: UInt
    let updatedAt: Date
    let sessionID: UUID
    let generation: Int
}

actor DraftRecoveryStore {
    static let shared = DraftRecoveryStore()
    static let currentSessionID = UUID()
    static let maximumDraftBytes = 2 * 1024 * 1024
    static let maximumDraftCount = 20
    static let maximumTotalBytes = 20 * 1024 * 1024
    static let retention: TimeInterval = 14 * 24 * 60 * 60
    private let directory: URL
    private let sessionsDirectory: URL
    private var latestGeneration: [UUID: Int] = [:]
    private var sessionHandle: FileHandle?
    private var recoveryWarnings: [String] = []

    init(directory: URL? = nil) {
        let base = directory ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("BriskEdit/Drafts", isDirectory: true)
        self.directory = base
        self.sessionsDirectory = base.appendingPathComponent("Sessions", isDirectory: true)
    }

    func save(id: UUID, generation: Int, fileURL: URL?, displayName: String, text: String,
              encoding: String.Encoding = .utf8) throws {
        guard generation >= latestGeneration[id, default: -1] else { return }
        latestGeneration[id] = generation
        guard text.lengthOfBytes(using: .utf8) <= Self.maximumDraftBytes else { throw DraftRecoveryError.draftTooLarge }
        try prepareDirectoriesAndSession()
        try prune()
        let active = activeSessionIDs()
        let existing = try decodedDrafts().filter { active.contains($0.sessionID) && $0.id != id }
        let existingBytes = existing.reduce(0) { $0 + $1.text.lengthOfBytes(using: .utf8) }
        guard existing.count < Self.maximumDraftCount,
              existingBytes + text.lengthOfBytes(using: .utf8) <= Self.maximumTotalBytes else {
            throw DraftRecoveryError.storageLimitReached
        }
        let draft = RecoverableDraft(id: id, filePath: fileURL?.path, displayName: displayName, text: text,
                                     encodingRawValue: encoding.rawValue, updatedAt: Date(),
                                     sessionID: Self.currentSessionID, generation: generation)
        let url = draftURL(id)
        try JSONEncoder().encode(draft).write(to: url, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
        try prune()
    }

    func remove(id: UUID, generation: Int) throws {
        guard generation >= latestGeneration[id, default: -1] else { return }
        latestGeneration[id] = generation
        let url = draftURL(id)
        if FileManager.default.fileExists(atPath: url.path) { try FileManager.default.removeItem(at: url) }
    }

    func recoverableDrafts(now: Date = Date()) throws -> [RecoverableDraft] {
        try prepareDirectoriesAndSession(); try prune(now: now)
        let active = activeSessionIDs()
        return try decodedDrafts().filter { !active.contains($0.sessionID) }.sorted { $0.updatedAt > $1.updatedAt }
    }

    func takeWarnings() -> [String] { defer { recoveryWarnings.removeAll() }; return recoveryWarnings }

    private func prepareDirectoriesAndSession() throws {
        try FileManager.default.createDirectory(at: sessionsDirectory, withIntermediateDirectories: true,
                                                attributes: [.posixPermissions: 0o700])
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: directory.path)
        let marker = sessionsDirectory.appendingPathComponent(Self.currentSessionID.uuidString)
        if sessionHandle == nil {
            if !FileManager.default.fileExists(atPath: marker.path) { _ = FileManager.default.createFile(atPath: marker.path, contents: nil) }
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: marker.path)
            let handle = try FileHandle(forUpdating: marker)
            guard flock(handle.fileDescriptor, LOCK_EX | LOCK_NB) == 0 else {
                try handle.close(); throw DraftRecoveryError.sessionLockUnavailable
            }
            sessionHandle = handle
        }
    }

    private func activeSessionIDs() -> Set<UUID> {
        guard let files = try? FileManager.default.contentsOfDirectory(at: sessionsDirectory, includingPropertiesForKeys: nil) else { return [] }
        var result = Set<UUID>()
        for file in files {
            guard let id = UUID(uuidString: file.lastPathComponent), let handle = try? FileHandle(forUpdating: file) else { continue }
            if id == Self.currentSessionID { result.insert(id); try? handle.close(); continue }
            if flock(handle.fileDescriptor, LOCK_EX | LOCK_NB) == 0 {
                flock(handle.fileDescriptor, LOCK_UN); try? handle.close()
                if id != Self.currentSessionID { try? FileManager.default.removeItem(at: file) }
            } else {
                result.insert(id); try? handle.close()
            }
        }
        return result
    }

    private func prune(now: Date = Date()) throws {
        let active = activeSessionIDs()
        var kept = 0, total = 0
        for draft in try decodedDrafts().sorted(by: { $0.updatedAt > $1.updatedAt }) {
            let size = draft.text.lengthOfBytes(using: .utf8)
            let remove = !active.contains(draft.sessionID) && (now.timeIntervalSince(draft.updatedAt) > Self.retention
                || kept >= Self.maximumDraftCount || total + size > Self.maximumTotalBytes)
            if remove { try FileManager.default.removeItem(at: draftURL(draft.id)) }
            else { kept += 1; total += size }
        }
    }

    private func decodedDrafts() throws -> [RecoverableDraft] {
        let urls = try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: [.fileSizeKey])
            .filter { $0.pathExtension == "json" }
        return try urls.compactMap { url in
            let size = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
            guard size <= Self.maximumDraftBytes * 6 + 65_536 else {
                recoveryWarnings.append("Recovery draft \(url.lastPathComponent) is too large to inspect and was preserved."); return nil
            }
            do {
                let draft = try JSONDecoder().decode(RecoverableDraft.self, from: Data(contentsOf: url, options: .mappedIfSafe))
                guard url.deletingPathExtension().lastPathComponent == draft.id.uuidString else {
                    recoveryWarnings.append("Recovery draft \(url.lastPathComponent) has an invalid identity and was preserved."); return nil
                }
                return draft
            } catch {
                recoveryWarnings.append("Recovery draft \(url.lastPathComponent) is unreadable and was preserved."); return nil
            }
        }
    }

    private func draftURL(_ id: UUID) -> URL { directory.appendingPathComponent(id.uuidString).appendingPathExtension("json") }
}

enum DraftRecoveryError: LocalizedError {
    case draftTooLarge
    case unreadableDraft(String)
    case sessionLockUnavailable
    case storageLimitReached
    var errorDescription: String? {
        switch self {
        case .draftTooLarge: "The draft exceeds the 2 MB recovery limit."
        case .unreadableDraft(let name): "Recovery draft \(name) is unreadable and was preserved."
        case .sessionLockUnavailable: "Draft recovery could not lock this app session."
        case .storageLimitReached: "Draft recovery reached its limit of 20 drafts or 20 MB. Save or discard another draft first."
        }
    }
}
