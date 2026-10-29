import UIKit
import XCTest
@testable import BankingLab

@MainActor
final class StatementViewControllerTests: XCTestCase {
    func testControllerLoadsAndRendersInitialPage() async throws {
        let fixture = try makeFixture()
        await fixture.repository.waitForRequests(1)
        XCTAssertEqual(fixture.viewModel.state, .loading)
        await fixture.repository.complete(0, with: .success(page()))
        await fixture.probe.wait(for: .loaded(page()))

        XCTAssertTrue(fixture.controller.view === fixture.view)
        XCTAssertEqual(fixture.controller.title, "Extrato")
        XCTAssertEqual(try table(in: fixture.view).numberOfRows(inSection: 0), 1)
        let cursors = await fixture.repository.cursors
        XCTAssertEqual(cursors, [nil])
        fixture.controller.stop()
    }

    func testRetryButtonReloadsAfterInitialFailure() async throws {
        let fixture = try makeFixture()
        await fixture.repository.waitForRequests(1)
        await fixture.repository.complete(0, with: .failure(URLError(.timedOut)))
        await fixture.probe.wait(for: .failed)
        let retry = try find("statement.retry", in: fixture.view, as: UIButton.self)
        retry.sendActions(for: .touchUpInside)
        await fixture.repository.waitForRequests(2)
        await fixture.repository.complete(1, with: .success(page()))
        await fixture.probe.wait(for: .loaded(page()))

        XCTAssertEqual(try table(in: fixture.view).numberOfRows(inSection: 0), 1)
        XCTAssertTrue(retry.isHidden)
        fixture.controller.stop()
    }

    func testPaginationButtonKeepsRowsOnErrorAndRetries() async throws {
        let fixture = try makeFixture()
        let initial = page(cursor: "next")
        await fixture.repository.waitForRequests(1)
        await fixture.repository.complete(0, with: .success(initial))
        await fixture.probe.wait(for: .loaded(initial))
        let button = try find("statement.load-more", in: fixture.view, as: UIButton.self)
        button.sendActions(for: .touchUpInside)
        await fixture.repository.waitForRequests(2)
        await fixture.repository.complete(1, with: .failure(URLError(.timedOut)))
        await fixture.probe.wait(for: .loaded(initial, pagination: .failed))
        XCTAssertEqual(try table(in: fixture.view).numberOfRows(inSection: 0), 1)
        button.sendActions(for: .touchUpInside)
        await fixture.repository.waitForRequests(3)
        let next = page(id: "b")
        await fixture.repository.complete(2, with: .success(next))
        await fixture.probe.wait(for: .loaded(StatementPage(items: initial.items + next.items, nextCursor: nil)))

        XCTAssertEqual(try table(in: fixture.view).numberOfRows(inSection: 0), 2)
        XCTAssertTrue(button.isHidden)
        let cursors = await fixture.repository.cursors
        XCTAssertEqual(cursors, [nil, "next", "next"])
        fixture.controller.stop()
    }

    func testRowSelectionReachesViewModelWithCurrentTransaction() async throws {
        let fixture = try makeFixture()
        await fixture.repository.waitForRequests(1)
        let expected = page()
        await fixture.repository.complete(0, with: .success(expected))
        await fixture.probe.wait(for: .loaded(expected))
        var selected: StatementTransaction?
        fixture.viewModel.onSelectTransaction = { selected = $0 }
        let table = try table(in: fixture.view)

        table.delegate?.tableView?(table, didSelectRowAt: IndexPath(row: 0, section: 0))

        XCTAssertEqual(selected, expected.items.first)
        fixture.controller.stop()
    }

    func testDisappearanceDoesNotStopPendingWorkOrReloadOnReturn() async throws {
        let fixture = try makeFixture()
        await fixture.repository.waitForRequests(1)
        fixture.controller.beginAppearanceTransition(false, animated: false)
        fixture.controller.endAppearanceTransition()
        await fixture.repository.complete(0, with: .success(page()))
        await fixture.probe.wait(for: .loaded(page()))
        fixture.controller.beginAppearanceTransition(true, animated: false)
        fixture.controller.endAppearanceTransition()

        XCTAssertEqual(fixture.viewModel.state, .loaded(page()))
        let cursors = await fixture.repository.cursors
        XCTAssertEqual(cursors, [nil])
        fixture.controller.stop()
    }

    func testStopCancelsInitialTaskAndDisconnectsEvents() async throws {
        let fixture = try makeFixture()
        await fixture.repository.waitForRequests(1)
        fixture.controller.stop()
        fixture.controller.stop()
        await fixture.repository.waitForCancellation()

        XCTAssertEqual(fixture.viewModel.state, .idle)
        XCTAssertNil(fixture.viewModel.onStateChange)
        XCTAssertNil(fixture.view.onRetry)
        XCTAssertNil(fixture.view.onLoadMore)
        XCTAssertNil(fixture.view.onSelectTransaction)
        await fixture.repository.complete(0, with: .success(page()))
    }

    func testStopCancelsPaginationTaskAndPreservesContent() async throws {
        let fixture = try makeFixture()
        let initial = page(cursor: "next")
        await fixture.repository.waitForRequests(1)
        await fixture.repository.complete(0, with: .success(initial))
        await fixture.probe.wait(for: .loaded(initial))
        fixture.view.onLoadMore?()
        await fixture.repository.waitForRequests(2)
        fixture.controller.stop()
        await fixture.repository.waitForCancellation()

        XCTAssertEqual(fixture.viewModel.state, .loaded(initial))
        await fixture.repository.complete(1, with: .success(page(id: "late")))
    }

    func testPendingTaskDoesNotKeepControllerAlive() async throws {
        let repository = ControllerRepository()
        let viewModel = StatementViewModel(repository: repository)
        var controller: StatementViewController? = StatementViewController(viewModel: viewModel, statementView: try makeView())
        weak let weakController = controller
        controller?.loadViewIfNeeded()
        await repository.waitForRequests(1)

        controller = nil
        await repository.waitForCancellation()

        XCTAssertNil(weakController)
        await repository.complete(0, with: .success(page()))
    }

    func testStoppedControllerDoesNotStartWhenLoadedLater() async throws {
        let repository = ControllerRepository()
        let controller = StatementViewController(viewModel: StatementViewModel(repository: repository), statementView: try makeView())
        controller.stop()
        controller.loadViewIfNeeded()

        let cursors = await repository.cursors
        XCTAssertTrue(cursors.isEmpty)
    }

    func testIntegratedControllerRendersInPhysicalWindow() async throws {
        let fixture = try makeFixture()
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let previous = scene.windows.first(where: \.isKeyWindow)
        let window = UIWindow(windowScene: scene)
        window.frame = scene.coordinateSpace.bounds
        let navigation = ControllerHostNavigation(rootViewController: fixture.controller)
        window.rootViewController = navigation
        window.makeKeyAndVisible()
        await navigation.waitForAppearance()
        defer {
            fixture.controller.stop()
            window.isHidden = true
            previous?.makeKeyAndVisible()
        }
        await fixture.repository.waitForRequests(1)
        await fixture.repository.complete(0, with: .success(page(cursor: "next")))
        await fixture.probe.wait(for: .loaded(page(cursor: "next")))
        window.layoutIfNeeded()

        XCTAssertEqual(try table(in: fixture.view).numberOfRows(inSection: 0), 1)
        let image = UIGraphicsImageRenderer(bounds: window.bounds).image { _ in
            window.drawHierarchy(in: window.bounds, afterScreenUpdates: true)
        }
        let attachment = XCTAttachment(image: image)
        attachment.name = "statement-controller-loaded"
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    private struct Fixture {
        let repository: ControllerRepository
        let viewModel: StatementViewModel
        let view: StatementView
        let controller: StatementViewController
        let probe: ControllerStateProbe
    }

    private func makeFixture() throws -> Fixture {
        let repository = ControllerRepository()
        let viewModel = StatementViewModel(repository: repository)
        let view = try makeView()
        let controller = StatementViewController(viewModel: viewModel, statementView: view)
        controller.loadViewIfNeeded()
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        controller.view.frame = scene.coordinateSpace.bounds
        controller.view.layoutIfNeeded()
        let probe = ControllerStateProbe(viewModel: viewModel)
        return Fixture(repository: repository, viewModel: viewModel, view: view, controller: controller, probe: probe)
    }

    private func makeView() throws -> StatementView {
        StatementView(currencyCode: "BRL", locale: Locale(identifier: "pt_BR"), timeZone: try XCTUnwrap(TimeZone(secondsFromGMT: 0)))
    }

    private func page(id: String = "a", cursor: String? = nil) -> StatementPage {
        StatementPage(items: [StatementTransaction(id: id, occurredAt: Date(timeIntervalSince1970: 1_793_275_200), description: "Transação de exemplo", amount: MonetaryAmount(cents: 12_345))], nextCursor: cursor)
    }

    private func table(in view: UIView) throws -> UITableView {
        try find("statement.list", in: view, as: UITableView.self)
    }

    private func find<T: UIView>(_ id: String, in root: UIView, as type: T.Type) throws -> T {
        func search(_ view: UIView) -> T? {
            if view.accessibilityIdentifier == id { return view as? T }
            return view.subviews.lazy.compactMap { search($0) }.first
        }
        return try XCTUnwrap(search(root), "Componente ausente: \(id)")
    }
}

@MainActor
private final class ControllerStateProbe {
    private var latest: StatementViewState
    private var waiters: [(StatementViewState, CheckedContinuation<Void, Never>)] = []

    init(viewModel: StatementViewModel) {
        latest = viewModel.state
        let render = viewModel.onStateChange
        viewModel.onStateChange = { [weak self] state in
            render?(state)
            self?.receive(state)
        }
    }

    func wait(for state: StatementViewState) async {
        if latest != state {
            await withCheckedContinuation { waiters.append((state, $0)) }
        }
    }

    private func receive(_ state: StatementViewState) {
        latest = state
        let ready = waiters.filter { $0.0 == state }
        waiters.removeAll { $0.0 == state }
        ready.forEach { $0.1.resume() }
    }
}

@MainActor
private final class ControllerHostNavigation: UINavigationController {
    private var appeared = false
    private var waiter: CheckedContinuation<Void, Never>?

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        appeared = true
        waiter?.resume()
        waiter = nil
    }

    func waitForAppearance() async {
        if !appeared {
            await withCheckedContinuation { waiter = $0 }
        }
    }
}

private actor ControllerRepository: StatementRepository {
    private(set) var cursors: [String?] = []
    private var responses: [Int: CheckedContinuation<StatementPage, any Error>] = [:]
    private var requestWaiters: [(Int, CheckedContinuation<Void, Never>)] = []
    private var cancelled = false
    private var cancellationWaiter: CheckedContinuation<Void, Never>?

    func fetchPage(cursor: String?) async throws -> StatementPage {
        let index = cursors.count
        cursors.append(cursor)
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                responses[index] = continuation
                let ready = requestWaiters.filter { $0.0 <= cursors.count }
                requestWaiters.removeAll { $0.0 <= cursors.count }
                ready.forEach { $0.1.resume() }
            }
        } onCancel: {
            Task { await self.recordCancellation() }
        }
    }

    func waitForRequests(_ count: Int) async {
        if cursors.count < count {
            await withCheckedContinuation { requestWaiters.append((count, $0)) }
        }
    }

    func complete(_ index: Int, with result: Result<StatementPage, any Error>) {
        responses.removeValue(forKey: index)?.resume(with: result)
    }

    func waitForCancellation() async {
        if !cancelled {
            await withCheckedContinuation { cancellationWaiter = $0 }
        }
    }

    private func recordCancellation() {
        cancelled = true
        cancellationWaiter?.resume()
        cancellationWaiter = nil
    }
}
