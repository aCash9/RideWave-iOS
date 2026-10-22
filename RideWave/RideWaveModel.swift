import Combine
import Foundation

// Screen navigation is separate from Spotify connection state.
enum RidePage: String {
    case setup, connect, ride
}

enum RideOrientation: String, CaseIterable, Identifiable {
    case auto, portrait, landscape
    var id: String { rawValue }
    var title: String { rawValue.capitalized }
}

@MainActor
final class RideWaveModel: ObservableObject {
    @Published var page: RidePage = .setup
    @Published var orientation: RideOrientation {
        didSet { defaults.set(orientation.rawValue, forKey: "ride_orientation") }
    }
    @Published var keepScreenAwake: Bool {
        didSet { defaults.set(keepScreenAwake, forKey: "ride_keep_awake") }
    }
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        orientation = RideOrientation(rawValue: defaults.string(forKey: "ride_orientation") ?? "") ?? .auto
        keepScreenAwake = defaults.object(forKey: "ride_keep_awake") as? Bool ?? true
        #if DEBUG
        if let index = ProcessInfo.processInfo.arguments.firstIndex(of: "-preview-page"),
           ProcessInfo.processInfo.arguments.indices.contains(index + 1),
           let requested = RidePage(rawValue: ProcessInfo.processInfo.arguments[index + 1]) {
            page = requested
        }
        #endif
    }

    func startRide(connected: Bool) { page = connected ? .ride : .connect }
    func connectionEstablished() { if page == .connect { page = .ride } }
    func closeRide() { page = .setup }
}
