import Foundation

/// Watches a single file for external modifications using a vnode dispatch
/// source. Atomic saves (the pattern used by BriskEdit itself and most editors)
/// replace the file's inode, which would silence a naive watcher — so this one
/// re-arms itself on `.delete`/`.rename`/`.revoke` by reopening the path.
///
/// The change handler is invoked off the main thread; callers hop to the main
/// actor themselves. There is no polling: the source sleeps until the kernel
/// reports an event.
/// All mutable state is confined to the private serial `queue`, so the type is
/// safe to hand to `@Sendable` dispatch handlers.
final class FileWatcher: @unchecked Sendable {
    private let path: String
    private let onChange: @Sendable () -> Void
    private let queue = DispatchQueue(label: "com.johannesgrof.briskedit.filewatcher")
    private var source: (any DispatchSourceFileSystemObject)?
    private var rearmAttempts = 0
    private var cancellationGeneration = 0
    private var isCancelled = false

    init?(url: URL, onChange: @escaping @Sendable () -> Void) {
        self.path = url.path
        self.onChange = onChange
        var started = false
        queue.sync { started = self.start() }
        guard started else { return nil }
    }

    func cancel() {
        queue.async { [weak self] in
            guard let self else { return }
            self.isCancelled = true
            self.cancellationGeneration &+= 1
            self.source?.cancel()
            self.source = nil
        }
    }

    deinit {
        source?.cancel()
    }

    /// Must run on `queue`.
    private func start() -> Bool {
        guard !isCancelled else { return false }
        let fd = open(path, O_EVTONLY)
        guard fd >= 0 else { return false }
        let src = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fd,
            eventMask: [.write, .extend, .delete, .rename, .revoke],
            queue: queue
        )
        src.setEventHandler { [weak self] in
            guard let self else { return }
            let flags = src.data
            self.onChange()
            // Inode replaced by an atomic save → the current fd is now stale;
            // reopen the path so we keep getting events for the new file.
            if flags.contains(.delete) || flags.contains(.rename) || flags.contains(.revoke) {
                self.rearm()
            }
        }
        src.setCancelHandler { close(fd) }
        source = src
        rearmAttempts = 0
        src.resume()
        return true
    }

    /// Must run on `queue`.
    private func rearm() {
        source?.cancel()
        source = nil
        rearmAttempts += 1
        let generation = cancellationGeneration
        // Atomic swaps normally settle immediately. Longer delete/recreate cycles
        // back off to avoid polling aggressively, but continue until cancellation.
        let delay = min(5.0, 0.05 * pow(2.0, Double(min(rearmAttempts - 1, 7))))
        queue.asyncAfter(deadline: .now() + delay) { [weak self] in
            guard let self, !self.isCancelled, self.cancellationGeneration == generation,
                  self.source == nil else { return }
            if self.start() {
                self.onChange()
            } else {
                self.rearm()
            }
        }
    }
}
