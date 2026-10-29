import UIKit
import XCTest
@testable import BankingLab

@MainActor
final class StatementViewTests: XCTestCase {
    func testLoadingShowsProgressWithoutRows() async throws {
        try await withView { view, table, _ in
            view.render(.loading)

            XCTAssertEqual(table.numberOfRows(inSection: 0), 0)
            XCTAssertTrue(try self.find("statement.initial-loading", in: view, as: UIActivityIndicatorView.self).isAnimating)
            XCTAssertEqual(try self.find("statement.status", in: view, as: UILabel.self).text, "Carregando extrato…")
            XCTAssertTrue(try self.find("statement.retry", in: view, as: UIButton.self).isHidden)
        }
    }

    func testEmptyStateHasNoRetryOrPagination() async throws {
        try await withView { view, table, _ in
            view.render(.empty)

            XCTAssertEqual(table.numberOfRows(inSection: 0), 0)
            XCTAssertEqual(try self.find("statement.status", in: view, as: UILabel.self).text, "Nenhuma transação para mostrar.")
            XCTAssertTrue(try self.find("statement.retry", in: view, as: UIButton.self).isHidden)
            XCTAssertTrue(try self.find("statement.load-more", in: view, as: UIButton.self).isHidden)
        }
    }

    func testInitialErrorEmitsRetry() async throws {
        try await withView { view, table, window in
            var retried = false
            view.onRetry = { retried = true }
            view.render(.failed)
            let button = try self.find("statement.retry", in: view, as: UIButton.self)

            XCTAssertEqual(table.numberOfRows(inSection: 0), 0)
            XCTAssertFalse(button.isHidden)
            button.sendActions(for: .touchUpInside)
            XCTAssertTrue(retried)
            self.attach(window, name: "statement-initial-error")
        }
    }

    func testLoadedRowsDisplayFormattedData() async throws {
        try await withView { view, table, window in
            view.render(.loaded(self.page()))
            window.layoutIfNeeded()
            let cell = try XCTUnwrap(table.cellForRow(at: IndexPath(row: 0, section: 0)))

            XCTAssertEqual(table.numberOfRows(inSection: 0), 2)
            XCTAssertEqual(cell.accessibilityIdentifier, "statement.transaction.first")
            XCTAssertEqual(cell.accessibilityLabel, "Compra de exemplo")
            XCTAssertTrue(try XCTUnwrap(cell.accessibilityValue).contains("R$"))
            XCTAssertTrue(try XCTUnwrap(cell.accessibilityValue).contains("123,45"))
            XCTAssertTrue(cell.isAccessibilityElement)
            XCTAssertTrue(cell.accessibilityTraits.contains(.button))
            self.attach(window, name: "statement-loaded-light")
        }
    }

    func testPaginationErrorPreservesRowsAndEmitsPaginationRetry() async throws {
        try await withView { view, table, window in
            var retriedInitial = false
            var retriedPagination = false
            view.onRetry = { retriedInitial = true }
            view.onLoadMore = { retriedPagination = true }
            view.render(.loaded(self.page(), pagination: .failed))
            let button = try self.find("statement.load-more", in: view, as: UIButton.self)

            XCTAssertEqual(table.numberOfRows(inSection: 0), 2)
            XCTAssertEqual(button.title(for: .normal), "Tentar novamente")
            XCTAssertFalse(button.isHidden)
            button.sendActions(for: .touchUpInside)
            XCTAssertTrue(retriedPagination)
            XCTAssertFalse(retriedInitial)
            self.attach(window, name: "statement-pagination-error")
        }
    }

    func testPaginationProgressKeepsRowsAndHidesAction() async throws {
        try await withView { view, table, _ in
            view.render(.loaded(self.page(), pagination: .loading))

            XCTAssertEqual(table.numberOfRows(inSection: 0), 2)
            XCTAssertTrue(try self.find("statement.pagination-loading", in: view, as: UIActivityIndicatorView.self).isAnimating)
            let button = try self.find("statement.load-more", in: view, as: UIButton.self)
            XCTAssertTrue(button.isHidden)
            XCTAssertFalse(button.isEnabled)
        }
    }

    func testFinalPageHidesPaginationAction() async throws {
        try await withView { view, table, _ in
            let final = StatementPage(items: self.page().items, nextCursor: nil)
            view.render(.loaded(final))

            XCTAssertEqual(table.numberOfRows(inSection: 0), 2)
            XCTAssertTrue(try self.find("statement.load-more", in: view, as: UIButton.self).isHidden)
        }
    }

    func testSameIDReconfiguresVisibleCell() async throws {
        try await withView { view, table, window in
            view.render(.loaded(self.page()))
            window.layoutIfNeeded()
            let updated = StatementTransaction(id: "first", occurredAt: Date(timeIntervalSince1970: 0), description: "Descrição atualizada", amount: MonetaryAmount(cents: 99_999))
            view.render(.loaded(StatementPage(items: [updated], nextCursor: nil)))
            window.layoutIfNeeded()
            let cell = try XCTUnwrap(table.cellForRow(at: IndexPath(row: 0, section: 0)))

            XCTAssertEqual(table.numberOfRows(inSection: 0), 1)
            XCTAssertEqual(cell.accessibilityIdentifier, "statement.transaction.first")
            XCTAssertEqual(cell.accessibilityLabel, "Descrição atualizada")
            XCTAssertTrue(try XCTUnwrap(cell.accessibilityValue).contains("999,99"))
        }
    }

    func testSelectionEmitsStableIDAfterReordering() async throws {
        try await withView { view, table, _ in
            var selected: String?
            view.onSelectTransaction = { selected = $0 }
            view.render(.loaded(self.page()))
            view.render(.loaded(StatementPage(items: Array(self.page().items.reversed()), nextCursor: nil)))

            table.delegate?.tableView?(table, didSelectRowAt: IndexPath(row: 0, section: 0))

            XCTAssertEqual(selected, "second")
        }
    }

    func testRepeatedIDsDoNotCreateDuplicateRows() async throws {
        try await withView { view, table, _ in
            let item = self.page().items[0]
            view.render(.loaded(StatementPage(items: [item, item], nextCursor: nil)))

            XCTAssertEqual(table.numberOfRows(inSection: 0), 1)
        }
    }

    func testErrorAfterContentClearsStaleRowsAndSelection() async throws {
        try await withView { view, table, _ in
            var selected: String?
            view.onSelectTransaction = { selected = $0 }
            view.render(.loaded(self.page()))
            view.render(.failed)
            table.delegate?.tableView?(table, didSelectRowAt: IndexPath(row: 0, section: 0))

            XCTAssertEqual(table.numberOfRows(inSection: 0), 0)
            XCTAssertNil(selected)
        }
    }

    func testLargeTextRendersRowsAndPaginationInDarkMode() async throws {
        try await withView(category: .accessibilityExtraExtraExtraLarge, style: .dark) { view, table, window in
            view.render(.loaded(self.page()))
            window.layoutIfNeeded()
            let cell = try XCTUnwrap(table.cellForRow(at: IndexPath(row: 0, section: 0)))
            let button = try self.find("statement.load-more", in: view, as: UIButton.self)

            XCTAssertEqual(view.traitCollection.preferredContentSizeCategory, .accessibilityExtraExtraExtraLarge)
            XCTAssertGreaterThan(cell.bounds.height, 110)
            XCTAssertGreaterThanOrEqual(button.bounds.height, 44)
            XCTAssertGreaterThan(try XCTUnwrap(button.titleLabel).font.pointSize, 17)
            self.attach(window, name: "statement-loaded-accessibility-dark")
        }
    }

    private func withView(
        category: UIContentSizeCategory = .large,
        style: UIUserInterfaceStyle = .light,
        body: (StatementView, UITableView, UIWindow) throws -> Void
    ) async throws {
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let previous = scene.windows.first(where: \.isKeyWindow)
        let window = UIWindow(windowScene: scene)
        window.frame = scene.coordinateSpace.bounds
        window.overrideUserInterfaceStyle = style
        let view = StatementView(currencyCode: "BRL", locale: Locale(identifier: "pt_BR"), timeZone: try XCTUnwrap(TimeZone(secondsFromGMT: 0)))
        let controller = SnapshotHostViewController()
        controller.title = "Extrato"
        controller.view = view
        let navigation = UINavigationController(rootViewController: controller)
        window.rootViewController = navigation
        controller.traitOverrides.preferredContentSizeCategory = category
        await withCheckedContinuation { continuation in
            controller.onAppear = { continuation.resume() }
            window.makeKeyAndVisible()
        }
        window.layoutIfNeeded()
        defer {
            window.isHidden = true
            previous?.makeKeyAndVisible()
        }
        let table = try find("statement.list", in: view, as: UITableView.self)
        try body(view, table, window)
    }

    private func find<T: UIView>(_ id: String, in root: UIView, as type: T.Type) throws -> T {
        func search(_ view: UIView) -> T? {
            if view.accessibilityIdentifier == id { return view as? T }
            return view.subviews.lazy.compactMap { search($0) }.first
        }
        return try XCTUnwrap(search(root), "Componente ausente: \(id)")
    }

    private func attach(_ window: UIWindow, name: String) {
        window.layoutIfNeeded()
        let image = UIGraphicsImageRenderer(bounds: window.bounds).image { _ in
            window.drawHierarchy(in: window.bounds, afterScreenUpdates: true)
        }
        let attachment = XCTAttachment(image: image)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    private func page() -> StatementPage {
        StatementPage(items: [
            StatementTransaction(id: "first", occurredAt: Date(timeIntervalSince1970: 1_793_275_200), description: "Compra de exemplo", amount: MonetaryAmount(cents: -12_345)),
            StatementTransaction(id: "second", occurredAt: Date(timeIntervalSince1970: 1_793_188_800), description: "Uma descrição longa para conferir a quebra de linha da transação", amount: MonetaryAmount(cents: .max))
        ], nextCursor: "next")
    }
}

@MainActor
private final class SnapshotHostViewController: UIViewController {
    var onAppear: (() -> Void)?

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        onAppear?()
        onAppear = nil
    }
}
