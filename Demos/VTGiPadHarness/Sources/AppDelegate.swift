import UIKit

/// The iPad harness for SwiftTerm's UIKit VTG view.
///
/// Not a product: a place to see `VectorTerminalView` draw on a real UIKit
/// screen, and to keep it honest while the rest of the iPad work lands. There
/// is no process and no shell here — iOS forbids both — so the view is fed
/// bytes the way any host would feed them.
@main
final class AppDelegate: UIResponder, UIApplicationDelegate {
    func application(
        _ application: UIApplication,
        configurationForConnecting session: UISceneSession,
        options: UIScene.ConnectionOptions
    ) -> UISceneConfiguration {
        let configuration = UISceneConfiguration(name: nil, sessionRole: session.role)
        configuration.delegateClass = SceneDelegate.self
        return configuration
    }
}

final class SceneDelegate: UIResponder, UIWindowSceneDelegate {
    var window: UIWindow?

    func scene(
        _ scene: UIScene,
        willConnectTo session: UISceneSession,
        options connectionOptions: UIScene.ConnectionOptions
    ) {
        guard let windowScene = scene as? UIWindowScene else {
            return
        }
        let window = UIWindow(windowScene: windowScene)
        window.rootViewController = HarnessViewController()
        window.makeKeyAndVisible()
        self.window = window
    }
}
