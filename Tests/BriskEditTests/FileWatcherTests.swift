import XCTest
@testable import BriskEdit

private final class WatcherProbe: @unchecked Sendable {
    private let lock = NSLock()
    private var existingEvents = 0
    let first: XCTestExpectation
    let second: XCTestExpectation?

    init(first: XCTestExpectation, second: XCTestExpectation? = nil) {
        self.first = first
        self.second = second
    }

    func recordExistingEvent() {
        let event = lock.withLock { existingEvents += 1; return existingEvents }
        if event == 1 { first.fulfill() }
        if event == 2 { second?.fulfill() }
    }
}

final class FileWatcherTests: XCTestCase {
    func testRearmsAfterLongDeleteGapAndObservesLaterWrite() throws {
        let url = temporaryFileURL()
        try Data("initial".utf8).write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }
        let rearmed = expectation(description: "watcher rearmed")
        let laterWrite = expectation(description: "later write observed")
        let probe = WatcherProbe(first: rearmed, second: laterWrite)
        let watcher = try XCTUnwrap(FileWatcher(url: url) {
            guard FileManager.default.fileExists(atPath: url.path) else { return }
            probe.recordExistingEvent()
        })

        try FileManager.default.removeItem(at: url)
        DispatchQueue.global().asyncAfter(deadline: .now() + 1.3) {
            try? Data("recreated".utf8).write(to: url)
        }
        wait(for: [rearmed], timeout: 4)
        try Data("changed".utf8).write(to: url, options: .atomic)
        wait(for: [laterWrite], timeout: 4)
        watcher.cancel()
    }

    func testCancelPreventsPendingRearm() throws {
        let url = temporaryFileURL()
        try Data("initial".utf8).write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }
        let unexpected = expectation(description: "event after cancellation")
        unexpected.isInverted = true
        let probe = WatcherProbe(first: unexpected)
        let watcher = try XCTUnwrap(FileWatcher(url: url) {
            if FileManager.default.fileExists(atPath: url.path) { probe.recordExistingEvent() }
        })

        try FileManager.default.removeItem(at: url)
        watcher.cancel()
        DispatchQueue.global().asyncAfter(deadline: .now() + 1.3) {
            try? Data("recreated".utf8).write(to: url)
            try? Data("changed".utf8).write(to: url, options: .atomic)
        }
        wait(for: [unexpected], timeout: 2.5)
    }

    private func temporaryFileURL() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("briskedit-watcher-\(UUID().uuidString)")
    }
}
