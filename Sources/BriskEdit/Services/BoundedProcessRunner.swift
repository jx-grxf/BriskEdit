import Darwin
import Foundation

struct BoundedProcessResult: Sendable {
    let terminationStatus: Int32
    let stdout: Data
    let stderr: Data
    let timedOut: Bool
    let outputLimitExceeded: Bool
}

private struct CappedDataSink {
    let limit: Int
    private(set) var storage = Data()
    private(set) var exceeded = false

    init(limit: Int) { self.limit = max(0, limit) }

    mutating func append(_ bytes: UnsafeRawBufferPointer) {
        let remaining = max(0, limit - storage.count)
        if remaining > 0 { storage.append(contentsOf: bytes.bindMemory(to: UInt8.self).prefix(remaining)) }
        if bytes.count > remaining { exceeded = true }
    }
}

/// Uses one nonblocking poll loop for process I/O. Process lifetime, stdin,
/// output and pipe EOF therefore share a deadline and spawn no blocking workers.
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
        var stdoutPipe = [Int32](repeating: -1, count: 2)
        var stderrPipe = [Int32](repeating: -1, count: 2)
        var stdinPipe = [Int32](repeating: -1, count: 2)
        guard pipe(&stdoutPipe) == 0, pipe(&stderrPipe) == 0 else {
            closePipe(&stdoutPipe); closePipe(&stderrPipe)
            return nil
        }
        if input != nil, pipe(&stdinPipe) != 0 {
            closePipe(&stdoutPipe); closePipe(&stderrPipe); closePipe(&stdinPipe)
            return nil
        }

        guard setNonBlocking(stdoutPipe[0]), setNonBlocking(stderrPipe[0]) else {
            closePipe(&stdoutPipe); closePipe(&stderrPipe); closePipe(&stdinPipe)
            return nil
        }
        if input != nil {
            guard setNonBlocking(stdinPipe[1]), fcntl(stdinPipe[1], F_SETNOSIGPIPE, 1) != -1 else {
                closePipe(&stdoutPipe); closePipe(&stderrPipe); closePipe(&stdinPipe)
                return nil
            }
        }

        let process = Process()
        process.executableURL = executableURL
        process.arguments = arguments
        process.currentDirectoryURL = currentDirectoryURL
        process.standardOutput = FileHandle(fileDescriptor: stdoutPipe[1], closeOnDealloc: false)
        process.standardError = FileHandle(fileDescriptor: stderrPipe[1], closeOnDealloc: false)
        process.standardInput = input == nil
            ? FileHandle.nullDevice
            : FileHandle(fileDescriptor: stdinPipe[0], closeOnDealloc: false)

        do { try process.run() } catch {
            closePipe(&stdoutPipe); closePipe(&stderrPipe); closePipe(&stdinPipe)
            return nil
        }
        closeDescriptor(&stdoutPipe[1])
        closeDescriptor(&stderrPipe[1])
        closeDescriptor(&stdinPipe[0])

        let deadline = ContinuousClock.now + .seconds(timeout)
        var stdout = CappedDataSink(limit: maximumStandardOutputBytes)
        var stderr = CappedDataSink(limit: maximumStandardErrorBytes)
        var inputOffset = 0
        var timedOut = false

        while true {
            drain(stdoutPipe[0], into: &stdout, storedDescriptor: &stdoutPipe[0])
            drain(stderrPipe[0], into: &stderr, storedDescriptor: &stderrPipe[0])
            if let input, stdinPipe[1] >= 0 {
                writeAvailable(input, offset: &inputOffset, descriptor: &stdinPipe[1])
            }

            if !process.isRunning && stdinPipe[1] < 0 && stdoutPipe[0] < 0 && stderrPipe[0] < 0 { break }
            if ContinuousClock.now >= deadline { timedOut = true; break }

            var descriptors = pollDescriptors(stdout: stdoutPipe[0], stderr: stderrPipe[0], stdin: stdinPipe[1])
            _ = poll(&descriptors, nfds_t(descriptors.count), 10)
        }

        closeDescriptor(&stdinPipe[1])
        closeDescriptor(&stdoutPipe[0])
        closeDescriptor(&stderrPipe[0])

        if timedOut, process.isRunning {
            process.terminate()
            let grace = ContinuousClock.now + .milliseconds(100)
            while process.isRunning && ContinuousClock.now < grace { usleep(2_000) }
            if process.isRunning {
                kill(process.processIdentifier, SIGKILL)
                let killGrace = ContinuousClock.now + .milliseconds(50)
                while process.isRunning && ContinuousClock.now < killGrace { usleep(2_000) }
            }
        }

        return BoundedProcessResult(
            terminationStatus: process.isRunning ? SIGKILL : process.terminationStatus,
            stdout: stdout.storage,
            stderr: stderr.storage,
            timedOut: timedOut,
            outputLimitExceeded: stdout.exceeded || stderr.exceeded
        )
    }

    private static func setNonBlocking(_ descriptor: Int32) -> Bool {
        let flags = fcntl(descriptor, F_GETFL)
        return flags >= 0 && fcntl(descriptor, F_SETFL, flags | O_NONBLOCK) != -1
    }

    private static func drain(_ descriptor: Int32, into sink: inout CappedDataSink,
                              storedDescriptor: inout Int32) {
        guard descriptor >= 0 else { return }
        var buffer = [UInt8](repeating: 0, count: 64 * 1024)
        for _ in 0..<16 {
            let count = buffer.withUnsafeMutableBytes { read(descriptor, $0.baseAddress, $0.count) }
            if count > 0 {
                buffer.withUnsafeBytes { sink.append(UnsafeRawBufferPointer(rebasing: $0.prefix(count))) }
            } else if count == 0 {
                closeDescriptor(&storedDescriptor)
                return
            } else if errno == EAGAIN || errno == EWOULDBLOCK {
                return
            } else if errno == EINTR {
                continue
            } else {
                closeDescriptor(&storedDescriptor)
                return
            }
        }
    }

    private static func writeAvailable(_ input: Data, offset: inout Int, descriptor: inout Int32) {
        guard descriptor >= 0 else { return }
        if offset >= input.count { closeDescriptor(&descriptor); return }
        let written = input.withUnsafeBytes { bytes in
            write(descriptor, bytes.baseAddress!.advanced(by: offset), input.count - offset)
        }
        if written > 0 {
            offset += written
            if offset == input.count { closeDescriptor(&descriptor) }
        } else if written < 0, errno != EAGAIN, errno != EWOULDBLOCK, errno != EINTR {
            closeDescriptor(&descriptor)
        }
    }

    private static func pollDescriptors(stdout: Int32, stderr: Int32, stdin: Int32) -> [pollfd] {
        var result: [pollfd] = []
        if stdout >= 0 { result.append(pollfd(fd: stdout, events: Int16(POLLIN | POLLHUP), revents: 0)) }
        if stderr >= 0 { result.append(pollfd(fd: stderr, events: Int16(POLLIN | POLLHUP), revents: 0)) }
        if stdin >= 0 { result.append(pollfd(fd: stdin, events: Int16(POLLOUT | POLLHUP), revents: 0)) }
        return result
    }

    private static func closeDescriptor(_ descriptor: inout Int32) {
        if descriptor >= 0 { close(descriptor); descriptor = -1 }
    }

    private static func closePipe(_ descriptors: inout [Int32]) {
        for index in descriptors.indices { closeDescriptor(&descriptors[index]) }
    }
}
