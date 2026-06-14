import Foundation

enum CLIInstallerError: LocalizedError {
    /// `/usr/local/bin` is missing or not writable without elevated rights — we
    /// surface the exact one-liner the user can paste into Terminal instead.
    case binDirectoryUnwritable(symlink: String, target: String)

    var errorDescription: String? {
        switch self {
        case let .binDirectoryUnwritable(symlink, target):
            let dir = (symlink as NSString).deletingLastPathComponent
            return """
            Couldn't write to \(dir). Run this once in Terminal to finish installing:

            sudo mkdir -p \(dir) && sudo ln -sf "\(target)" "\(symlink)"
            """
        }
    }
}

/// Installs a `brisk` command-line launcher (the `code .` equivalent) so a
/// folder or files can be opened in BriskEdit straight from the terminal. We
/// keep a tiny launcher script in Application Support and symlink it into
/// `/usr/local/bin`; the script normalizes its arguments to absolute paths and
/// hands them to Launch Services, which routes them into the app.
@MainActor
enum CLIInstaller {
    static let symlinkPath = "/usr/local/bin/brisk"
    static let bundleIdentifier = "com.johannesgrof.briskedit"

    /// Where the launcher script itself lives (the symlink points here).
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

    /// True when the symlink exists and points at our current launcher script.
    static var isInstalled: Bool {
        let fm = FileManager.default
        guard let destination = try? fm.destinationOfSymbolicLink(atPath: symlinkPath) else { return false }
        let resolved = URL(fileURLWithPath: destination).standardizedFileURL
        return resolved == launcherScriptURL.standardizedFileURL
    }

    /// Writes the launcher script and (re)creates the `/usr/local/bin/brisk`
    /// symlink. Throws `CLIInstallerError.binDirectoryUnwritable` with a copyable
    /// `sudo` command when `/usr/local/bin` can't be written without admin.
    static func install() throws {
        let fm = FileManager.default
        let scriptURL = launcherScriptURL

        try fm.createDirectory(at: scriptURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try launcherScript.write(to: scriptURL, atomically: true, encoding: .utf8)
        try fm.setAttributes([.posixPermissions: 0o755], ofItemAtPath: scriptURL.path)

        let binDir = (symlinkPath as NSString).deletingLastPathComponent
        var isDirectory: ObjCBool = false
        let binExists = fm.fileExists(atPath: binDir, isDirectory: &isDirectory)
        guard binExists, isDirectory.boolValue, fm.isWritableFile(atPath: binDir) else {
            throw CLIInstallerError.binDirectoryUnwritable(symlink: symlinkPath, target: scriptURL.path)
        }

        // Replace any stale symlink/file left from a previous install.
        if (try? fm.destinationOfSymbolicLink(atPath: symlinkPath)) != nil || fm.fileExists(atPath: symlinkPath) {
            try? fm.removeItem(atPath: symlinkPath)
        }
        do {
            try fm.createSymbolicLink(atPath: symlinkPath, withDestinationPath: scriptURL.path)
        } catch {
            throw CLIInstallerError.binDirectoryUnwritable(symlink: symlinkPath, target: scriptURL.path)
        }
    }

    /// Removes the symlink (the script in Application Support is harmless to keep).
    static func uninstall() throws {
        let fm = FileManager.default
        if (try? fm.destinationOfSymbolicLink(atPath: symlinkPath)) != nil {
            try fm.removeItem(atPath: symlinkPath)
        }
    }
}
