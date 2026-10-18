import Combine
import Foundation

// Screen navigation is separate from Spotify connection state.
enum RidePage: String {
    case tutorial, connect, ride
}

@MainActor
final class RideWaveModel: ObservableObject {
    @Published var page: RidePage
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard, hasPlaybackSession: Bool = false) {
        self.defaults = defaults
        page = hasPlaybackSession ? .ride : (defaults.bool(forKey: "onboarding_seen") ? .connect : .tutorial)
        #if DEBUG
        if let index = ProcessInfo.processInfo.arguments.firstIndex(of: "-preview-page"),
           ProcessInfo.processInfo.arguments.indices.contains(index + 1),
           let requested = RidePage(rawValue: ProcessInfo.processInfo.arguments[index + 1]) {
            page = requested
        }
        #endif
    }

    func completeTutorial() {
        defaults.set(true, forKey: "onboarding_seen")
        page = .connect
    }

}
