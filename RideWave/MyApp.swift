import SwiftUI

@main struct MyApp: App {
    @UIApplicationDelegateAdaptor(RideAppDelegate.self) private var appDelegate

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}
