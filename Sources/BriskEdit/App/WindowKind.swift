import Foundation

/// Identifies a workspace window so the scene can tell the launch/restored
/// window apart from windows the user explicitly opens. Only the primary window
/// reopens the last folder + session; user-created windows start empty and do
/// not clobber the persisted session.
enum WindowKind: Hashable, Codable {
    case primary
    case secondary(UUID)

    var restoresSession: Bool {
        if case .primary = self { true } else { false }
    }
}

/// Bridges the SwiftUI `openWindow` action to non-SwiftUI call sites (the Dock
/// menu, the app delegate). A live window stores the action on appear; AppKit
/// callbacks invoke it on the main actor.
@MainActor
final class NewWindowCoordinator {
    static let shared = NewWindowCoordinator()
    var open: (() -> Void)?

    private init() {}

    func openNewWindow() {
        open?()
    }
}
