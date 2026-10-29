import UIKit
import XCTest
@testable import BankingLab

@MainActor
final class StatementCoordinatorTests: XCTestCase {
    func testStartPushesOneStatementAndIsIdempotent() async throws {
        try await withNavigation { navigation in
            let coordinator = try self.makeCoordinator(navigation)
            coordinator.start(animated: false)
            coordinator.start(animated: false)

            XCTAssertEqual(navigation.viewControllers.count, 2)
            XCTAssertTrue(navigation.topViewController === coordinator.rootViewController)
            XCTAssertTrue(navigation.delegate === coordinator)
            coordinator.stop()
        }
    }

    func testOpeningAndPoppingDetailsKeepsStatementFlowAlive() async throws {
        try await withNavigation { navigation in
            let coordinator = try self.makeCoordinator(navigation)
            var finished = false
            coordinator.onFinish = { finished = true }
            coordinator.start(animated: false)
            let root = coordinator.rootViewController
            coordinator.showDetails(self.transaction(), animated: false)

            let details = try XCTUnwrap(navigation.topViewController as? StatementDetailsViewController)
            details.loadViewIfNeeded()
            XCTAssertEqual(details.title, "Detalhes")
            XCTAssertTrue(navigation.viewControllers.contains(where: { $0 === root }))
            XCTAssertFalse(finished)
            _ = navigation.popViewController(animated: false)
            XCTAssertTrue(navigation.topViewController === root)
            XCTAssertNotNil(coordinator.rootViewController)
            XCTAssertFalse(finished)
            coordinator.stop()
        }
    }

    func testPoppingStatementFinishesAndDetachesDelegate() async throws {
        try await withNavigation { navigation in
            let coordinator = try self.makeCoordinator(navigation)
            var finishCount = 0
            coordinator.start(animated: true)
            await self.waitForTransition(navigation)
            let finished = XCTestExpectation(description: "Fluxo encerrado pelo UIKit")
            coordinator.onFinish = {
                finishCount += 1
                finished.fulfill()
            }
            _ = navigation.popViewController(animated: true)
            let result = await XCTWaiter.fulfillment(of: [finished], timeout: 5)
            XCTAssertEqual(result, .completed)
            if result != .completed { coordinator.stop() }

            XCTAssertEqual(finishCount, 1)
            XCTAssertNil(coordinator.rootViewController)
            XCTAssertNil(navigation.delegate)
            coordinator.stop()
            XCTAssertEqual(finishCount, 1)
        }
    }

    func testStopRemovesEntireChildFlowAndPreventsFurtherNavigation() async throws {
        try await withNavigation { navigation in
            let account = navigation.topViewController
            let coordinator = try self.makeCoordinator(navigation)
            coordinator.start(animated: false)
            coordinator.showDetails(self.transaction(), animated: false)
            coordinator.stop()
            coordinator.showDetails(self.transaction(), animated: false)
            coordinator.start(animated: false)

            XCTAssertEqual(navigation.viewControllers.count, 1)
            XCTAssertTrue(navigation.topViewController === account)
            XCTAssertNil(coordinator.rootViewController)
        }
    }

    func testPopWithPendingWorkCancelsTaskAndClearsRoot() async throws {
        try await withNavigation { navigation in
            let repository = NavigationRepository(holdResponse: true)
            let coordinator = try self.makeCoordinator(navigation, repository: repository)
            coordinator.start(animated: true)
            await self.waitForTransition(navigation)
            coordinator.rootViewController?.loadViewIfNeeded()
            await repository.waitForRequest()
            let finished = XCTestExpectation(description: "Fluxo pendente encerrado")
            coordinator.onFinish = { finished.fulfill() }
            _ = navigation.popViewController(animated: true)
            let result = await XCTWaiter.fulfillment(of: [finished], timeout: 5)
            XCTAssertEqual(result, .completed)
            if result != .completed { coordinator.stop() }
            await repository.waitForCancellation()

            XCTAssertNil(coordinator.rootViewController)
            XCTAssertEqual(navigation.viewControllers.count, 1)
            await repository.releaseResponse()
        }
    }

    func testFinishedCoordinatorCanBeReleased() async throws {
        try await withNavigation { navigation in
            var coordinator: StatementCoordinator? = try self.makeCoordinator(navigation)
            weak let weakCoordinator = coordinator
            coordinator?.start(animated: false)
            autoreleasepool { _ = navigation.popViewController(animated: false) }
            coordinator = nil

            XCTAssertNil(weakCoordinator)
        }
    }

    func testFactoryCreatesDetailsFromSelectedTransaction() throws {
        let factory = try makeFactory(repository: NavigationRepository())
        let details = factory.makeDetails(transaction: transaction())
        details.loadViewIfNeeded()
        func labels(_ view: UIView) -> [UILabel] {
            (view as? UILabel).map { [$0] } ?? view.subviews.flatMap { labels($0) }
        }
        let content = labels(details.view)
        XCTAssertEqual(content.first { $0.accessibilityIdentifier == "statement.details.description" }?.text, "Compra de exemplo")
        XCTAssertEqual(content.first { $0.accessibilityIdentifier == "statement.details.id" }?.text, "Identificador: demo-1")
        XCTAssertTrue(content.first { $0.accessibilityIdentifier == "statement.details.amount" }?.text?.contains("123,45") == true)
    }

    private func makeCoordinator(_ navigation: UINavigationController, repository: any StatementRepository = NavigationRepository()) throws -> StatementCoordinator {
        StatementCoordinator(navigationController: navigation, factory: try makeFactory(repository: repository))
    }

    private func makeFactory(repository: any StatementRepository) throws -> StatementFactory {
        StatementFactory(repository: repository, currencyCode: "BRL", locale: Locale(identifier: "pt_BR"), timeZone: try XCTUnwrap(TimeZone(secondsFromGMT: 0)))
    }

    private func transaction() -> StatementTransaction {
        StatementTransaction(id: "demo-1", occurredAt: Date(timeIntervalSince1970: 0), description: "Compra de exemplo", amount: MonetaryAmount(cents: -12_345))
    }

    private func waitForTransition(_ navigation: UINavigationController) async {
        guard let transition = navigation.transitionCoordinator else { return }
        await withCheckedContinuation { continuation in
            let registered = transition.animate(alongsideTransition: nil) { _ in continuation.resume() }
            if !registered { continuation.resume() }
        }
    }

    private func withNavigation(_ body: (UINavigationController) async throws -> Void) async throws {
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let previous = scene.windows.first(where: \.isKeyWindow)
        let window = UIWindow(windowScene: scene)
        window.frame = scene.coordinateSpace.bounds
        let account = UIViewController()
        account.title = "Conta"
        account.view.backgroundColor = .systemBackground
        let navigation = NavigationTestHost(rootViewController: account)
        window.rootViewController = navigation
        window.makeKeyAndVisible()
        await navigation.waitForAppearance()
        defer {
            window.isHidden = true
            previous?.makeKeyAndVisible()
        }
        try await body(navigation)
    }
}

@MainActor
private final class NavigationTestHost: UINavigationController {
    private var appeared = false
    private var waiter: CheckedContinuation<Void, Never>?

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        appeared = true
        waiter?.resume()
        waiter = nil
    }

    func waitForAppearance() async {
        if !appeared { await withCheckedContinuation { waiter = $0 } }
    }
}

private actor NavigationRepository: StatementRepository {
    private let holdResponse: Bool
    private var requested = false
    private var cancelled = false
    private var response: CheckedContinuation<StatementPage, any Error>?
    private var requestWaiter: CheckedContinuation<Void, Never>?
    private var cancellationWaiter: CheckedContinuation<Void, Never>?

    init(holdResponse: Bool = false) { self.holdResponse = holdResponse }

    func fetchPage(cursor: String?) async throws -> StatementPage {
        requested = true
        requestWaiter?.resume()
        requestWaiter = nil
        guard holdResponse else { return StatementPage(items: [], nextCursor: nil) }
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { response = $0 }
        } onCancel: {
            Task { await self.recordCancellation() }
        }
    }

    func waitForRequest() async {
        if !requested { await withCheckedContinuation { requestWaiter = $0 } }
    }

    func waitForCancellation() async {
        if !cancelled { await withCheckedContinuation { cancellationWaiter = $0 } }
    }

    func releaseResponse() {
        response?.resume(returning: StatementPage(items: [], nextCursor: nil))
        response = nil
    }

    private func recordCancellation() {
        cancelled = true
        cancellationWaiter?.resume()
        cancellationWaiter = nil
    }
}
