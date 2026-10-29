import UIKit

@MainActor
final class AppCoordinator {
    let navigationController: UINavigationController
    private(set) var statementCoordinator: StatementCoordinator?
    private let account: AccountViewController
    private let statementFactory: StatementFactory
    private var hasStarted = false
    private var isStopped = false

    init(navigationController: UINavigationController, account: AccountViewController, statementFactory: StatementFactory) {
        self.navigationController = navigationController
        self.account = account
        self.statementFactory = statementFactory
    }

    func start() {
        guard !hasStarted, !isStopped else { return }
        hasStarted = true
        account.onShowStatement = { [weak self] in self?.showStatement() }
        navigationController.setViewControllers([account], animated: false)
    }

    func showStatement(animated: Bool = true) {
        guard hasStarted, !isStopped, statementCoordinator == nil else { return }
        let coordinator = StatementCoordinator(navigationController: navigationController, factory: statementFactory)
        statementCoordinator = coordinator
        coordinator.onFinish = { [weak self] in self?.statementCoordinator = nil }
        coordinator.start(animated: animated)
    }

    func stop() {
        guard !isStopped else { return }
        isStopped = true
        account.onShowStatement = nil
        statementCoordinator?.onFinish = nil
        statementCoordinator?.stop()
        statementCoordinator = nil
    }
}
