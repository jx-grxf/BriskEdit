import Darwin
import Foundation

struct BoundedProcessResult: Sendable {
    let terminationStatus: Int32
    let stdout: Data
    let stderr: Data
    let timedOut: Bool
    let outputLimitExceeded: Bool
}

private final class CappedDataSink: @unchecked Sendable {
    private let lock = NSLock()
    private let limit: Int
    private var storage = Data()
    private var exceeded = false

    init(limit: Int) {
        self.limit = max(0, limit)
    }

    func append(_ data: Data) {
        lock.lock()
        defer { lock.unlock() }
        let remaining = max(0, limit - storage.count)
        if remaining > 0 {
            storage.append(contentsOf: data.prefix(remaining))
        }
        if data.count > remaining {
            exceeded = true
        }
    }

    func snapshot() -> (data: Data, exceeded: Bool) {
        lock.lock()
        defer { lock.unlock() }
        return (storage, exceeded)
    }
}

enum BoundedProcessRunner {
    static func run(
        executableURL: URL,
        arguments: [String],
        currentDirectoryURL: URL? = nil,
        input: Data? = nil,
        timeout: TimeInterval,
        maximumStandardOutputBytes: Int,
        maximumStandardErrorBytes: Int
    ) -> BoundedProcessResult? {
        let process = Process()
        process.executableURL = executableURL
        process.arguments = arguments
        process.currentDirectoryURL = currentDirectoryURL

        let stdin = input == nil ? nil : Pipe()
        let stdout = Pipe()
        let stderr = Pipe()
        process.standardInput = stdin ?? FileHandle.nullDevice
        process.standardOutput = stdout
        process.standardError = stderr

        let stdoutSink = CappedDataSink(limit: maximumStandardOutputBytes)
        let stderrSink = CappedDataSink(limit: maximumStandardErrorBytes)
        let readers = DispatchGroup()
        drain(stdout.fileHandleForReading, into: stdoutSink, group: readers)
        drain(stderr.fileHandleForReading, into: stderrSink, group: readers)

        let terminated = DispatchSemaphore(value: 0)
        process.terminationHandler = { _ in terminated.signal() }

        do {
            try process.run()
        } catch {
            try? stdin?.fileHandleForWriting.close()
            try? stdout.fileHandleForWriting.close()
            try? stderr.fileHandleForWriting.close()
            readers.wait()
            return nil
        }

        if let input, let stdin {
            let handle = stdin.fileHandleForWriting
            DispatchQueue.global(qos: .userInitiated).async {
                try? handle.write(contentsOf: input)
                try? handle.close()
            }
        }

        let timedOut = terminated.wait(timeout: .now() + timeout) == .timedOut
        if timedOut {
            process.terminate()
            if terminated.wait(timeout: .now() + 1) == .timedOut {
                kill(process.processIdentifier, SIGKILL)
                _ = terminated.wait(timeout: .now() + 1)
            }
        }

        readers.wait()
        let capturedStdout = stdoutSink.snapshot()
        let capturedStderr = stderrSink.snapshot()
        return BoundedProcessResult(
            terminationStatus: process.terminationStatus,
            stdout: capturedStdout.data,
            stderr: capturedStderr.data,
            timedOut: timedOut,
            outputLimitExceeded: capturedStdout.exceeded || capturedStderr.exceeded
        )
    }

    private static func drain(_ handle: FileHandle, into sink: CappedDataSink, group: DispatchGroup) {
        group.enter()
        DispatchQueue.global(qos: .userInteractive).async {
            defer { group.leave() }
            while let data = try? handle.read(upToCount: 64 * 1024), !data.isEmpty {
                sink.append(data)
            }
        }
    }
}
