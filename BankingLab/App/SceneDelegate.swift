import UIKit

@MainActor
final class SceneDelegate: UIResponder, UIWindowSceneDelegate {
    var window: UIWindow?
    private var coordinator: AppCoordinator?

    func scene(
        _ scene: UIScene,
        willConnectTo session: UISceneSession,
        options connectionOptions: UIScene.ConnectionOptions
    ) {
        guard let windowScene = scene as? UIWindowScene else { return }

        let window = UIWindow(windowScene: windowScene)
        let coordinator = AppCompositionRoot.makeCoordinator()
        self.coordinator = coordinator
        window.rootViewController = coordinator.navigationController
        self.window = window
        coordinator.start()
        window.makeKeyAndVisible()
    }

    func sceneDidDisconnect(_ scene: UIScene) {
        coordinator?.stop()
        coordinator = nil
        window = nil
    }
}
