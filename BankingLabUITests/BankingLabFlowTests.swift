import XCTest

@MainActor
final class BankingLabFlowTests: XCTestCase {
    func testAccountStatementPaginationDetailsAndReturn() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launch()
        let openStatement = app.buttons["account.statement"]
        XCTAssertTrue(openStatement.waitForExistence(timeout: 10))
        XCTAssertTrue((app.staticTexts["account.balance"].value as? String)?.contains("2.500,00") == true)
        capture(app, name: "account-installed-app")
        openStatement.tap()

        let table = app.tables["statement.list"]
        XCTAssertTrue(table.waitForExistence(timeout: 5))
        let credit = table.cells["statement.transaction.demo-credit"]
        XCTAssertTrue(credit.waitForExistence(timeout: 5))
        XCTAssertEqual(table.cells.count, 3)
        credit.tap()
        let amount = app.staticTexts["statement.details.amount"]
        XCTAssertTrue(amount.waitForExistence(timeout: 5))
        XCTAssertTrue((amount.value as? String)?.contains("3.500,00") == true)
        let description = app.staticTexts["statement.details.description"]
        XCTAssertGreaterThanOrEqual(description.frame.minX, 16)
        XCTAssertLessThanOrEqual(description.frame.maxX, app.frame.maxX - 16)
        capture(app, name: "details-installed-app")
        app.navigationBars["Detalhes"].buttons.element(boundBy: 0).tap()

        XCTAssertTrue(table.waitForExistence(timeout: 5))
        let loadMore = app.buttons["statement.load-more"]
        XCTAssertTrue(loadMore.waitForExistence(timeout: 5))
        loadMore.tap()
        let market = table.cells["statement.transaction.demo-market"]
        let updated = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label == %@", "Mercado — valor atualizado"), object: market)
        XCTAssertEqual(XCTWaiter.wait(for: [updated], timeout: 5), .completed)
        XCTAssertEqual(table.cells.count, 5)
        XCTAssertFalse(loadMore.exists)
        capture(app, name: "statement-paginated-installed-app")
        market.tap()
        XCTAssertTrue(amount.waitForExistence(timeout: 5))
        XCTAssertTrue((amount.value as? String)?.contains("92,35") == true)
        app.navigationBars["Detalhes"].buttons.element(boundBy: 0).tap()
        app.navigationBars["Extrato"].buttons.element(boundBy: 0).tap()

        XCTAssertTrue(openStatement.waitForExistence(timeout: 5))
        openStatement.tap()
        XCTAssertTrue(credit.waitForExistence(timeout: 5))
        XCTAssertEqual(table.cells.count, 3)
        XCTAssertTrue(loadMore.exists)
        credit.tap()
        XCTAssertTrue(amount.waitForExistence(timeout: 5))
    }

    private func capture(_ app: XCUIApplication, name: String) {
        app.navigationBars.firstMatch.tap()
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
