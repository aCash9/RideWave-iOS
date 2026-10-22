import SwiftUI
import UIKit

final class RideAppDelegate: NSObject, UIApplicationDelegate {
    static var orientationMask: UIInterfaceOrientationMask = .allButUpsideDown

    func application(_ application: UIApplication, supportedInterfaceOrientationsFor window: UIWindow?) -> UIInterfaceOrientationMask {
        Self.orientationMask
    }
}

// Resolve the scene from this view's window, rather than choosing an unrelated scene.
struct RideOrientationController: UIViewControllerRepresentable {
    let orientation: RideOrientation
    let onError: (String?) -> Void

    func makeUIViewController(context: Context) -> Controller { Controller() }
    func updateUIViewController(_ controller: Controller, context: Context) {
        controller.onError = onError
        controller.setOrientation(orientation)
    }

    final class Controller: UIViewController {
        var onError: (String?) -> Void = { _ in }
        private var orientation: RideOrientation = .auto
        private var applied: RideOrientation?

        override func viewDidAppear(_ animated: Bool) {
            super.viewDidAppear(animated)
            apply()
        }

        func setOrientation(_ value: RideOrientation) {
            orientation = value
            apply()
        }

        private func apply() {
            guard let scene = viewIfLoaded?.window?.windowScene, applied != orientation else { return }
            applied = orientation
            let requested = orientation
            let mask: UIInterfaceOrientationMask = switch orientation {
            case .auto: .allButUpsideDown
            case .portrait: .portrait
            case .landscape: .landscape
            }
            RideAppDelegate.orientationMask = mask
            scene.windows.forEach { $0.rootViewController?.setNeedsUpdateOfSupportedInterfaceOrientations() }
            scene.requestGeometryUpdate(.iOS(interfaceOrientations: mask)) { [weak self] _ in
                Task { @MainActor in
                    guard let self, self.orientation == requested else { return }
                    self.onError("iOS could not change orientation in this window. Try fullscreen mode.")
                }
            }
        }
    }
}
