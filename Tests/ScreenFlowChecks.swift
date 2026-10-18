import Foundation

@main
struct ScreenFlowChecks {
    @MainActor static func main() {
        let suite = "RideWave.ScreenFlowChecks.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let model = RideWaveModel(defaults: defaults)
        precondition(model.page == .tutorial)
        model.completeTutorial()
        precondition(model.page == .connect)
        precondition(RideWaveModel(defaults: defaults).page == .connect)
        model.page = .ride
        precondition(RideWaveModel(defaults: defaults).page == .connect)
        defaults.set(true, forKey: "spotify_authorized")
        precondition(RideWaveModel(defaults: defaults).page == .connect)
        precondition(RideWaveModel(defaults: defaults, hasPlaybackSession: true).page == .ride)
        precondition(RideWaveModel(defaults: defaults, hasPlaybackSession: false).page == .connect)
        defaults.removeObject(forKey: "onboarding_seen")
        precondition(RideWaveModel(defaults: defaults, hasPlaybackSession: true).page == .ride)
        precondition(RideWaveModel(defaults: defaults, hasPlaybackSession: false).page == .tutorial)
        print("Screen flow checks passed, including restored and absent playback sessions")
    }
}
