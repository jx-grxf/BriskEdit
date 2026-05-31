import Foundation
import Observation
import Sparkle

@MainActor
@Observable
final class UpdateService: NSObject {
    enum Channel: String, CaseIterable, Identifiable {
        case stable
        case beta
        var id: String { rawValue }
        var displayName: String {
            switch self {
            case .stable: "Stable"
            case .beta: "Beta"
            }
        }
    }

    private let controller: SPUStandardUpdaterController
    private let updaterDelegate: UpdaterDelegate

    /// Display version of an update Sparkle has found that the user has neither
    /// installed nor skipped yet. Survives "Remind Me Later" so the window
    /// toolbar can keep offering the update; cleared on skip/install.
    private(set) var availableUpdateVersion: String?
    var isUpdateAvailable: Bool { availableUpdateVersion != nil }

    var channel: Channel {
        didSet {
            UserDefaults.standard.set(channel.rawValue, forKey: Keys.channel)
            updaterDelegate.channel = channel
            controller.updater.resetUpdateCycle()
        }
    }
    var automaticallyChecksForUpdates: Bool {
        get { controller.updater.automaticallyChecksForUpdates }
        set { controller.updater.automaticallyChecksForUpdates = newValue }
    }
    var lastCheckDate: Date? { controller.updater.lastUpdateCheckDate }

    override init() {
        let storedChannel = UserDefaults.standard.string(forKey: Keys.channel)
            .flatMap(Channel.init(rawValue:)) ?? .stable
        let delegate = UpdaterDelegate(channel: storedChannel)
        self.updaterDelegate = delegate
        self.channel = storedChannel
        self.controller = SPUStandardUpdaterController(
            startingUpdater: true,
            updaterDelegate: delegate,
            userDriverDelegate: nil
        )
        super.init()
        delegate.onFoundUpdate = { [weak self] version in
            self?.availableUpdateVersion = version
        }
        delegate.onUserChoice = { [weak self] keepsReminder in
            if !keepsReminder { self?.availableUpdateVersion = nil }
        }
        // Default-on background checks come from Info.plist `SUEnableAutomaticChecks`
        // (which also skips the first-run opt-in prompt). We deliberately do NOT
        // force the flag here so the Settings toggle (a user preference Sparkle
        // persists) is respected across launches.
    }

    /// Manual / toolbar-triggered check. When an update is already pending this
    /// re-presents the standard update dialog immediately.
    func checkForUpdates() {
        controller.checkForUpdates(nil)
    }

    private enum Keys {
        static let channel = "updates.channel"
    }
}

/// Bridges Sparkle's `SPUUpdaterDelegate` callbacks to the @MainActor
/// `UpdateService`. Sparkle delivers these on the main thread.
private final class UpdaterDelegate: NSObject, SPUUpdaterDelegate {
    var channel: UpdateService.Channel
    /// Called with the display version when a valid update is found.
    var onFoundUpdate: ((String) -> Void)?
    /// Called when the user acts on the update dialog. `true` means the choice
    /// keeps the update pending (Remind Me Later); `false` clears it (Skip/Install).
    var onUserChoice: ((Bool) -> Void)?

    init(channel: UpdateService.Channel) {
        self.channel = channel
    }

    func allowedChannels(for updater: SPUUpdater) -> Set<String> {
        switch channel {
        case .stable: ["stable"]
        case .beta: ["stable", "beta"]
        }
    }

    func updater(_ updater: SPUUpdater, didFindValidUpdate item: SUAppcastItem) {
        let version = item.displayVersionString
        MainActor.assumeIsolated { onFoundUpdate?(version) }
    }

    func updater(
        _ updater: SPUUpdater,
        userDidMake choice: SPUUserUpdateChoice,
        forUpdate updateItem: SUAppcastItem,
        state: SPUUserUpdateState
    ) {
        let keepsReminder = (choice == .dismiss)
        MainActor.assumeIsolated { onUserChoice?(keepsReminder) }
    }
}
