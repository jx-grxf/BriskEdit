import Foundation
import Observation
import Sparkle

@MainActor
@Observable
final class UpdateService: NSObject {
    enum Channel: String, CaseIterable, Identifiable {
        case stable
        case beta
        /// Fixed for the separate nightly app; never selectable in a release build.
        case nightly
        var id: String { rawValue }
        var displayName: String {
            switch self {
            case .stable: "Stable"
            case .beta: "Beta"
            case .nightly: "Nightly"
            }
        }

        /// Channels a release build can switch between in Settings.
        static let selectableChannels: [Channel] = [.stable, .beta]
    }

    /// How often the nightly app looks for new builds. Sparkle never schedules
    /// checks more often than hourly, so the frequent cadence adds quiet
    /// background checks in between.
    enum NightlyCheckCadence: String, CaseIterable, Identifiable {
        case frequent
        case hourly
        case daily
        var id: String { rawValue }
        var displayName: String {
            switch self {
            case .frequent: "Every 15 minutes"
            case .hourly: "Every hour"
            case .daily: "Every day"
            }
        }

        var scheduledInterval: TimeInterval { self == .daily ? 86_400 : 3_600 }

        /// Extra background checks between Sparkle's own scheduled checks.
        var backgroundCheckInterval: Duration? { self == .frequent ? .seconds(15 * 60) : nil }
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
            availableUpdateVersion = nil
            updaterDelegate.channel = channel
            controller.updater.resetUpdateCycle()
        }
    }
    var automaticallyChecksForUpdates: Bool {
        get { controller.updater.automaticallyChecksForUpdates }
        set {
            controller.updater.automaticallyChecksForUpdates = newValue
            applyNightlySchedule()
        }
    }
    /// Stored mirror of Sparkle's persisted automatic download setting, so the
    /// Settings toggle refreshes (Sparkle's property is not observable).
    var automaticallyDownloadsUpdates: Bool {
        didSet {
            controller.updater.automaticallyDownloadsUpdates = automaticallyDownloadsUpdates
            applyNightlySchedule()
        }
    }
    var nightlyCheckCadence: NightlyCheckCadence {
        didSet {
            UserDefaults.standard.set(nightlyCheckCadence.rawValue, forKey: Keys.nightlyCheckCadence)
            applyNightlySchedule()
        }
    }
    @ObservationIgnored private var backgroundCheckTask: Task<Void, Never>?
    /// Mirror of Sparkle's `lastUpdateCheckDate`. Sparkle exposes that only as a
    /// plain (non-`@Observable`) property, so a computed pass-through never
    /// triggered a SwiftUI refresh — the "Last check" row stayed stale after a
    /// check. We snapshot it here and refresh on every finished update cycle.
    private(set) var lastCheckDate: Date?

    override init() {
        let distribution = AppDistribution.current
        if distribution == .nightly {
            // Nightly builds download in the background and install on quit.
            // A registered default never overrides a choice Sparkle has persisted
            // from its update dialog.
            UserDefaults.standard.register(defaults: ["SUAutomaticallyUpdate": true])
        }
        let storedChannel = Self.initialChannel(
            storedValue: UserDefaults.standard.string(forKey: Keys.channel),
            bundleVersion: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String,
            distribution: distribution
        )
        let delegate = UpdaterDelegate(channel: storedChannel)
        self.updaterDelegate = delegate
        self.channel = storedChannel
        self.lastCheckDate = nil
        self.automaticallyDownloadsUpdates = false
        self.nightlyCheckCadence = UserDefaults.standard.string(forKey: Keys.nightlyCheckCadence)
            .flatMap(NightlyCheckCadence.init(rawValue:)) ?? .frequent
        self.controller = SPUStandardUpdaterController(
            startingUpdater: true,
            updaterDelegate: delegate,
            userDriverDelegate: nil
        )
        super.init()
        self.lastCheckDate = controller.updater.lastUpdateCheckDate
        self.automaticallyDownloadsUpdates = controller.updater.automaticallyDownloadsUpdates
        delegate.onCheckCompleted = { [weak self] date in
            Task { @MainActor in self?.lastCheckDate = date }
        }
        delegate.onFoundUpdate = { [weak self] version in
            Task { @MainActor in self?.availableUpdateVersion = version }
        }
        delegate.onUserChoice = { [weak self] keepsReminder in
            Task { @MainActor in
                if !keepsReminder { self?.availableUpdateVersion = nil }
            }
        }
        delegate.onNoPendingUpdate = { [weak self] in
            Task { @MainActor in self?.availableUpdateVersion = nil }
        }
        // Default-on background checks come from Info.plist `SUEnableAutomaticChecks`
        // (which also skips the first-run opt-in prompt). We deliberately do NOT
        // force the flag here so the Settings toggle (a user preference Sparkle
        // persists) is respected across launches.
        applyNightlySchedule()
    }

    /// Nightly builds land shortly after every change on dev. Applies the chosen
    /// cadence to Sparkle's schedule and, for the frequent cadence, runs quiet
    /// background checks in between. Those only run while updates install
    /// automatically; otherwise each check could raise the update dialog again.
    private func applyNightlySchedule() {
        guard channel == .nightly else { return }
        controller.updater.updateCheckInterval = nightlyCheckCadence.scheduledInterval
        backgroundCheckTask?.cancel()
        backgroundCheckTask = nil
        guard let interval = nightlyCheckCadence.backgroundCheckInterval,
              controller.updater.automaticallyChecksForUpdates,
              automaticallyDownloadsUpdates else { return }
        backgroundCheckTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: interval, tolerance: .seconds(60))
                guard !Task.isCancelled else { return }
                self?.checkInBackground()
            }
        }
    }

    private func checkInBackground() {
        let updater = controller.updater
        guard updater.automaticallyChecksForUpdates, updater.canCheckForUpdates, !updater.sessionInProgress else {
            return
        }
        updater.checkForUpdatesInBackground()
    }

    nonisolated static func initialChannel(
        storedValue: String?,
        bundleVersion: String?,
        distribution: AppDistribution = .release
    ) -> Channel {
        if distribution == .nightly { return .nightly }
        if let storedValue, let stored = Channel(rawValue: storedValue), stored != .nightly { return stored }
        return bundleVersion?.contains("-beta.") == true ? .beta : .stable
    }

    /// Manual / toolbar-triggered check. When an update is already pending this
    /// re-presents the standard update dialog immediately.
    func checkForUpdates() {
        controller.checkForUpdates(nil)
    }

    private enum Keys {
        static let channel = "updates.channel"
        static let nightlyCheckCadence = "updates.nightlyCheckCadence"
    }
}

/// Bridges Sparkle's `SPUUpdaterDelegate` callbacks to `UpdateService`; the
/// closures hop back to the main actor before touching observable state.
private final class UpdaterDelegate: NSObject, SPUUpdaterDelegate {
    var channel: UpdateService.Channel
    /// Called with the display version when a valid update is found.
    var onFoundUpdate: ((String) -> Void)?
    /// Called when the user acts on the update dialog. `true` means the choice
    /// keeps the update pending (Remind Me Later); `false` clears it (Skip/Install).
    var onUserChoice: ((Bool) -> Void)?
    /// Called when Sparkle reports no usable update or aborts the cycle.
    var onNoPendingUpdate: (() -> Void)?
    /// Called at the end of every update cycle with Sparkle's latest check date,
    /// so the service can keep its observable `lastCheckDate` in sync.
    var onCheckCompleted: ((Date?) -> Void)?

    init(channel: UpdateService.Channel) {
        self.channel = channel
    }

    func allowedChannels(for updater: SPUUpdater) -> Set<String> {
        switch channel {
        // Stable releases live on Sparkle's default channel (no tag), which is
        // always visible — so the stable channel adds no extra channels. Beta
        // users additionally opt into "beta", and still see default (stable)
        // items, so they roll forward onto a newer stable build automatically.
        case .stable: []
        case .beta: ["beta"]
        // The nightly feed tags every item "nightly", so a release build that
        // somehow read it would still never see those items.
        case .nightly: ["nightly"]
        }
    }

    /// Beta builds poll a composite feed containing the latest beta and stable
    /// items. The bundle's
    /// `SUFeedURL` points at the `latest` GitHub release (stable only — GitHub's
    /// "latest" never resolves to a prerelease). Betas live behind the moving
    /// `beta` release, so on the beta channel we swap the path to that combined
    /// feed. This lets beta users advance to a newer stable release as well.
    /// Returning nil keeps the bundle default: the stable `latest` feed for
    /// release builds, the rolling `nightly` feed for the nightly app.
    func feedURLString(for updater: SPUUpdater) -> String? {
        guard channel == .beta else { return nil }
        let bundleFeed = Bundle.main.object(forInfoDictionaryKey: "SUFeedURL") as? String
        return bundleFeed?.replacingOccurrences(of: "releases/latest/download", with: "releases/download/beta")
            ?? "https://github.com/jx-grxf/BriskEdit/releases/download/beta/appcast.xml"
    }

    func updater(_ updater: SPUUpdater, didFindValidUpdate item: SUAppcastItem) {
        let version = item.displayVersionString
        onFoundUpdate?(version)
    }

    func updater(
        _ updater: SPUUpdater,
        userDidMake choice: SPUUserUpdateChoice,
        forUpdate updateItem: SUAppcastItem,
        state: SPUUserUpdateState
    ) {
        let keepsReminder = (choice == .dismiss)
        onUserChoice?(keepsReminder)
    }

    func updaterDidNotFindUpdate(_ updater: SPUUpdater, error: Error) {
        onNoPendingUpdate?()
    }

    func updater(_ updater: SPUUpdater, didAbortWithError error: Error) {
        onNoPendingUpdate?()
    }

    func updater(_ updater: SPUUpdater, didFinishUpdateCycleFor updateCheck: SPUUpdateCheck, error: Error?) {
        onCheckCompleted?(updater.lastUpdateCheckDate)
    }
}
