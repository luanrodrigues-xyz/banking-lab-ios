import UIKit
import XCTest
@testable import BankingLab

@MainActor
final class AppCoordinatorTests: XCTestCase {
    func testCompositionStartsOnAccount() {
        let coordinator = AppCompositionRoot.makeCoordinator()
        coordinator.start()
        coordinator.start()

        XCTAssertEqual(coordinator.navigationController.viewControllers.count, 1)
        XCTAssertTrue(coordinator.navigationController.topViewController is AccountViewController)
        XCTAssertNil(coordinator.statementCoordinator)
        coordinator.stop()
    }

    func testAccountButtonOpensStatementOnce() throws {
        let coordinator = AppCompositionRoot.makeCoordinator()
        coordinator.start()
        let account = try XCTUnwrap(coordinator.navigationController.topViewController as? AccountViewController)
        account.loadViewIfNeeded()
        account.onShowStatement?()
        let first = coordinator.statementCoordinator
        account.onShowStatement?()

        XCTAssertNotNil(first)
        XCTAssertTrue(coordinator.statementCoordinator === first)
        XCTAssertTrue(coordinator.navigationController.topViewController is StatementViewController)
        coordinator.stop()
    }

    func testStopReleasesChildAndDisconnectsAccount() throws {
        let coordinator = AppCompositionRoot.makeCoordinator()
        coordinator.start()
        let account = try XCTUnwrap(coordinator.navigationController.topViewController as? AccountViewController)
        coordinator.showStatement(animated: false)
        weak let child = coordinator.statementCoordinator

        coordinator.stop()
        coordinator.stop()
        coordinator.showStatement(animated: false)

        XCTAssertNil(coordinator.statementCoordinator)
        XCTAssertNil(child)
        XCTAssertNil(account.onShowStatement)
        XCTAssertEqual(coordinator.navigationController.viewControllers.count, 1)
    }

    func testStoppedAppCannotRestartFlow() {
        let coordinator = AppCompositionRoot.makeCoordinator()
        coordinator.stop()
        coordinator.start()
        coordinator.showStatement(animated: false)

        XCTAssertTrue(coordinator.navigationController.viewControllers.isEmpty)
        XCTAssertNil(coordinator.statementCoordinator)
    }

    func testAccountDisplaysInjectedBalance() throws {
        let account = AccountViewController(balance: MonetaryAmount(cents: 12_345), currencyCode: "BRL", locale: Locale(identifier: "pt_BR"))
        account.loadViewIfNeeded()
        func labels(_ view: UIView) -> [UILabel] {
            (view as? UILabel).map { [$0] } ?? view.subviews.flatMap { labels($0) }
        }

        XCTAssertTrue(labels(account.view).first { $0.accessibilityIdentifier == "account.balance" }?.text?.contains("123,45") == true)
    }
}
