import Foundation

@main
struct ScreenFlowChecks {
    @MainActor static func main() {
        let suite = "RideWave.ScreenFlowChecks.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let model = RideWaveModel(defaults: defaults)
        precondition(model.page == .setup && model.orientation == .auto && model.keepScreenAwake)
        model.startRide(connected: false)
        precondition(model.page == .connect)
        model.connectionEstablished()
        precondition(model.page == .ride)
        model.closeRide()
        model.connectionEstablished()
        precondition(model.page == .setup, "Late connections must not skip setup")
        model.startRide(connected: true)
        precondition(model.page == .ride)
        model.orientation = .landscape
        model.keepScreenAwake = false
        let restored = RideWaveModel(defaults: defaults)
        precondition(restored.page == .setup && restored.orientation == .landscape && !restored.keepScreenAwake)
        restored.orientation = .portrait
        precondition(RideWaveModel(defaults: defaults).orientation == .portrait)
        defaults.set("unknown", forKey: "ride_orientation")
        defaults.set(true, forKey: "onboarding_seen")
        precondition(RideWaveModel(defaults: defaults).orientation == .auto)
        precondition(RideWaveModel(defaults: defaults).page == .setup)
        print("Setup routing and preference persistence checks passed")
    }
}
