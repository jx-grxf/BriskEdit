import Foundation

enum CLIInstallerError: LocalizedError {
    /// The user dismissed the macOS authorization dialog.
    case authorizationCancelled
    /// Couldn't link into any writable location and the privileged fallback
    /// failed too.
    case failed(String)

    var errorDescription: String? {
        switch self {
        case .authorizationCancelled:
            return "Installation was cancelled."
        case let .failed(message):
            return message
        }
    }
}

/// Installs a `brisk` command-line launcher so a folder or files can be opened
/// in BriskEdit straight from the terminal. We keep a tiny launcher script in
/// Application Support and symlink it into the first writable directory that is
/// already on the user's `PATH` — preferring a home-owned directory so the
/// common case needs no privileges at all. Only when nothing on `PATH` is
/// writable do we fall back to a native admin prompt for `/usr/local/bin`.
enum CLIInstaller {
    static let bundleIdentifier = "com.johannesgrof.briskedit"
    /// Privileged fallback location, used only when nothing on PATH is writable.
    static let fallbackSymlinkPath = "/usr/local/bin/brisk"

    /// Where the launcher script itself lives (every symlink points here).
    static var launcherScriptURL: URL {
        let support = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)
            .first ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Library/Application Support")
        return support
            .appendingPathComponent("BriskEdit", isDirectory: true)
            .appendingPathComponent("brisk")
    }

    /// The launcher shell script. Resolves each argument to an absolute path so
    /// `brisk .` and relative paths work from any working directory, then passes
    /// them to `open` (which starts the app if needed). Kept as a value so it is
    /// unit-testable without touching the filesystem.
    static let launcherScript = """
    #!/bin/bash
    # BriskEdit command-line launcher — opens files and folders in BriskEdit.
    set -euo pipefail
    bundle_id="\(bundleIdentifier)"
    if [ "$#" -eq 0 ]; then
      exec open -b "$bundle_id"
    fi
    paths=()
    for arg in "$@"; do
      if [ -e "$arg" ]; then
        dir=$(cd "$(dirname "$arg")" >/dev/null 2>&1 && pwd)
        paths+=("$dir/$(basename "$arg")")
      else
        echo "brisk: no such file or directory: $arg" >&2
      fi
    done
    if [ "${#paths[@]}" -eq 0 ]; then
      exit 1
    fi
    exec open -b "$bundle_id" "${paths[@]}"
    """

    /// Cheap, shell-free check: is any known location a symlink to our script?
    static var isInstalled: Bool {
        let fm = FileManager.default
        let target = launcherScriptURL.standardizedFileURL
        for path in knownSymlinkPaths() {
            if let destination = try? fm.destinationOfSymbolicLink(atPath: path),
               URL(fileURLWithPath: destination).standardizedFileURL == target {
                return true
            }
        }
        return false
    }

    /// Writes the launcher script and links it into a writable `PATH` directory.
    /// Runs off the main actor; the privileged fallback hops back to the main
    /// actor for the authorization dialog.
    static func install() async throws {
        switch unprivilegedInstall() {
        case .installed:
            return
        case let .failed(message):
            throw CLIInstallerError.failed(message)
        case let .needsAdmin(scriptPath):
            try await runAdminInstall(scriptPath: scriptPath)
        }
    }

    /// Removes every symlink that points at our launcher script.
    static func uninstall() async throws {
        let privileged = unprivilegedUninstall()
        if !privileged.isEmpty {
            let command = privileged.map { "rm -f '\($0)'" }.joined(separator: " && ")
            try await runWithAdminPrivileges(command)
        }
        UserDefaults.standard.removeObject(forKey: installedPathKey)
    }

    // MARK: - Unprivileged work (off the main actor)

    private enum InstallOutcome {
        case installed
        case needsAdmin(scriptPath: String)
        case failed(String)
    }

    private static func unprivilegedInstall() -> InstallOutcome {
        let fm = FileManager.default
        let scriptURL = launcherScriptURL
        do {
            try fm.createDirectory(at: scriptURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            try launcherScript.write(to: scriptURL, atomically: true, encoding: .utf8)
            try fm.setAttributes([.posixPermissions: 0o755], ofItemAtPath: scriptURL.path)
        } catch {
            return .failed(error.localizedDescription)
        }

        guard let dir = writableDirectoryOnPath() else {
            return .needsAdmin(scriptPath: scriptURL.path)
        }
        let link = dir.appendingPathComponent("brisk").path
        do {
            if (try? fm.destinationOfSymbolicLink(atPath: link)) != nil || fm.fileExists(atPath: link) {
                try? fm.removeItem(atPath: link)
            }
            try fm.createSymbolicLink(atPath: link, withDestinationPath: scriptURL.path)
        } catch {
            return .needsAdmin(scriptPath: scriptURL.path)
        }
        UserDefaults.standard.set(link, forKey: installedPathKey)
        return .installed
    }

    /// Removes writable symlinks immediately and returns any that need elevation.
    private static func unprivilegedUninstall() -> [String] {
        let fm = FileManager.default
        let target = launcherScriptURL.standardizedFileURL
        var privileged: [String] = []
        for path in knownSymlinkPaths() {
            guard let destination = try? fm.destinationOfSymbolicLink(atPath: path),
                  URL(fileURLWithPath: destination).standardizedFileURL == target else { continue }
            if fm.isWritableFile(atPath: (path as NSString).deletingLastPathComponent) {
                try? fm.removeItem(atPath: path)
            } else {
                privileged.append(path)
            }
        }
        return privileged
    }

    // MARK: - Locations

    private static let installedPathKey = "cli.installedPath"

    /// Candidate symlink locations checked without spawning a shell: the path we
    /// recorded at install time plus the conventional dev `bin` directories.
    private static func knownSymlinkPaths() -> [String] {
        let home = NSHomeDirectory()
        var paths = [
            "/opt/homebrew/bin/brisk",
            "/usr/local/bin/brisk",
            "\(home)/.local/bin/brisk",
            "\(home)/bin/brisk",
        ]
        if let recorded = UserDefaults.standard.string(forKey: installedPathKey) {
            paths.insert(recorded, at: 0)
        }
        return paths
    }

    /// The first directory on the login-shell `PATH` we can write to, preferring
    /// home-owned directories so no privilege escalation is required.
    private static func writableDirectoryOnPath() -> URL? {
        let fm = FileManager.default
        let home = NSHomeDirectory()
        let dirs = loginShellPathDirectories()
        func isWritableDirectory(_ path: String) -> Bool {
            var isDirectory: ObjCBool = false
            return fm.fileExists(atPath: path, isDirectory: &isDirectory)
                && isDirectory.boolValue
                && fm.isWritableFile(atPath: path)
        }
        for dir in dirs where dir.hasPrefix(home) && isWritableDirectory(dir) {
            return URL(fileURLWithPath: dir)
        }
        for dir in dirs where isWritableDirectory(dir) {
            return URL(fileURLWithPath: dir)
        }
        return nil
    }

    /// The login shell's `PATH`, so we link into a directory the user's terminal
    /// will actually search (a GUI app's own `PATH` is just `/usr/bin:/bin:…`).
    private static func loginShellPathDirectories() -> [String] {
        let shell = ProcessInfo.processInfo.environment["SHELL"] ?? "/bin/zsh"
        let process = Process()
        process.executableURL = URL(fileURLWithPath: shell)
        process.arguments = ["-lic", "echo $PATH"]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = Pipe()
        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            return []
        }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        guard let output = String(data: data, encoding: .utf8) else { return [] }
        return output
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .split(separator: ":")
            .map(String.init)
    }

    // MARK: - Privileged fallback (main actor)

    @MainActor
    private static func runAdminInstall(scriptPath: String) throws {
        let dir = (fallbackSymlinkPath as NSString).deletingLastPathComponent
        try runWithAdminPrivileges("mkdir -p '\(dir)' && ln -sf '\(scriptPath)' '\(fallbackSymlinkPath)'")
        UserDefaults.standard.set(fallbackSymlinkPath, forKey: installedPathKey)
    }

    /// Runs a shell command via the native macOS authorization dialog (password
    /// or Touch ID) — no Terminal `sudo` required.
    @MainActor
    private static func runWithAdminPrivileges(_ command: String) throws {
        let escaped = command.replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
        let source = "do shell script \"\(escaped)\" with administrator privileges"
        var errorInfo: NSDictionary?
        guard let script = NSAppleScript(source: source) else {
            throw CLIInstallerError.failed("Couldn't build the install command.")
        }
        script.executeAndReturnError(&errorInfo)
        guard let errorInfo else { return }
        let code = errorInfo[NSAppleScript.errorNumber] as? Int ?? 0
        if code == -128 { throw CLIInstallerError.authorizationCancelled }
        let message = errorInfo[NSAppleScript.errorMessage] as? String ?? "Installation failed."
        throw CLIInstallerError.failed(message)
    }
}
