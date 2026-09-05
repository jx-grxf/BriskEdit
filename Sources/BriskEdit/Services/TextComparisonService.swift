import Foundation

enum TextComparisonError: LocalizedError {
    case tooLarge
    case failed(String)

    var errorDescription: String? {
        switch self {
        case .tooLarge: "Comparison supports text up to 4 MiB per side."
        case .failed(let message): message
        }
    }
}

enum TextComparisonService {
    static let maximumBytes = 4 * 1024 * 1024

    static func compareWithDisk(file: URL, text: String) async throws -> String {
        try await Task.detached(priority: .userInitiated) {
            let size = try file.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
            guard size <= maximumBytes else { throw TextComparisonError.tooLarge }
            var encoding: String.Encoding = .utf8
            let disk = try String(contentsOf: file, usedEncoding: &encoding)
            return try unifiedDiff(original: disk, updated: text)
        }.value
    }

    /// Runs off the main actor. Preserve line endings and terminal newlines so
    /// the comparison does not hide changes that would be written on save.
    static func unifiedDiff(original: String, updated: String) throws -> String {
        guard original.utf8.count <= maximumBytes, updated.utf8.count <= maximumBytes else {
            throw TextComparisonError.tooLarge
        }
        guard original != updated else { return "" }
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("brisk-diff-\(UUID())")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true,
                                              attributes: [.posixPermissions: 0o700])
        defer { try? FileManager.default.removeItem(at: directory) }
        let old = directory.appendingPathComponent("original")
        let new = directory.appendingPathComponent("updated")
        try original.write(to: old, atomically: true, encoding: .utf8)
        try updated.write(to: new, atomically: true, encoding: .utf8)
        guard let result = BoundedProcessRunner.run(
            executableURL: URL(fileURLWithPath: "/usr/bin/diff"),
            arguments: ["-u", "-L", "Disk", "-L", "Editor", old.path, new.path],
            timeout: 5, maximumStandardOutputBytes: 4 * maximumBytes,
            maximumStandardErrorBytes: 16 * 1024
        ) else { throw TextComparisonError.failed("Could not start the comparison tool.") }
        guard !result.timedOut, !result.outputLimitExceeded, result.terminationStatus <= 1,
              let output = String(data: result.stdout, encoding: .utf8) else {
            throw TextComparisonError.failed("The comparison could not finish within its time or output limit.")
        }
        return output
    }
}
