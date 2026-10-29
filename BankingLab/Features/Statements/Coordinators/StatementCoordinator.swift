import UIKit

@MainActor
final class StatementCoordinator: NSObject, UINavigationControllerDelegate {
    var onFinish: (@MainActor () -> Void)?
    private(set) var rootViewController: StatementViewController?

    private let navigationController: UINavigationController
    private let factory: StatementFactory
    private var hasStarted = false

    init(navigationController: UINavigationController, factory: StatementFactory) {
        self.navigationController = navigationController
        self.factory = factory
        super.init()
    }

    func start(animated: Bool = true) {
        guard !hasStarted else { return }
        hasStarted = true
        let controller = factory.makeStatement { [weak self] transaction in
            self?.showDetails(transaction)
        }
        rootViewController = controller
        navigationController.delegate = self
        navigationController.pushViewController(controller, animated: animated)
    }

    func showDetails(_ transaction: StatementTransaction, animated: Bool = true) {
        guard let rootViewController, navigationController.topViewController === rootViewController else { return }
        navigationController.pushViewController(factory.makeDetails(transaction: transaction), animated: animated)
    }

    func stop() {
        finish(removingScreens: true)
    }

    func navigationController(_ navigationController: UINavigationController, didShow viewController: UIViewController, animated: Bool) {
        guard let rootViewController,
              !navigationController.viewControllers.contains(where: { $0 === rootViewController }) else { return }
        finish(removingScreens: false)
    }

    private func finish(removingScreens: Bool) {
        guard let root = rootViewController else { return }
        rootViewController = nil
        root.stop()
        if navigationController.delegate === self { navigationController.delegate = nil }
        if removingScreens,
           let index = navigationController.viewControllers.firstIndex(where: { $0 === root }) {
            navigationController.setViewControllers(Array(navigationController.viewControllers.prefix(index)), animated: false)
        }
        let completion = onFinish
        onFinish = nil
        completion?()
    }
}
