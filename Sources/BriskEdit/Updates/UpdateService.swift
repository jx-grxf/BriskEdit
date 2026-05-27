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
    private let feedDelegate: FeedDelegate
    var channel: Channel {
        didSet {
            UserDefaults.standard.set(channel.rawValue, forKey: Keys.channel)
            feedDelegate.channel = channel
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
        let delegate = FeedDelegate(channel: storedChannel)
        self.feedDelegate = delegate
        self.channel = storedChannel
        self.controller = SPUStandardUpdaterController(
            startingUpdater: true,
            updaterDelegate: delegate,
            userDriverDelegate: nil
        )
        super.init()
    }

    func checkForUpdates() {
        controller.checkForUpdates(nil)
    }

    private enum Keys {
        static let channel = "updates.channel"
    }
}

private final class FeedDelegate: NSObject, SPUUpdaterDelegate {
    var channel: UpdateService.Channel

    init(channel: UpdateService.Channel) {
        self.channel = channel
    }

    func allowedChannels(for updater: SPUUpdater) -> Set<String> {
        switch channel {
        case .stable: ["stable"]
        case .beta: ["stable", "beta"]
        }
    }
}
