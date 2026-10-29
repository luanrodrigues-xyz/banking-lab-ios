import XCTest

@MainActor
final class BankingLabAccessibilityTests: XCTestCase {
    func testAccountAccessibilityAudit() throws {
        let app = launch()
        try app.performAccessibilityAudit()
    }

    func testStatementAccessibilityAudit() throws {
        let app = launch()
        openStatement(app)
        try app.performAccessibilityAudit()
    }

    func testDetailsAccessibilityAudit() throws {
        let app = launch()
        openStatement(app)
        app.tables["statement.list"].cells["statement.transaction.demo-credit"].tap()
        XCTAssertTrue(app.staticTexts["statement.details.amount"].waitForExistence(timeout: 5))
        app.navigationBars.firstMatch.tap()
        try app.performAccessibilityAudit()
    }

    func testLandscapeAccountStatementAndDetails() {
        let app = launch()
        XCUIDevice.shared.orientation = .landscapeLeft
        defer { XCUIDevice.shared.orientation = .portrait }
        let button = app.buttons["account.statement"]
        if !button.isHittable { app.scrollViews.firstMatch.swipeUp() }
        XCTAssertTrue(button.isHittable)
        capture(name: "account-landscape")
        openStatement(app)
        let credit = app.tables["statement.list"].cells["statement.transaction.demo-credit"]
        XCTAssertTrue(credit.isHittable)
        credit.tap()
        let amount = app.staticTexts["statement.details.amount"]
        XCTAssertTrue(amount.waitForExistence(timeout: 5))
        XCTAssertTrue(amount.isHittable)
        app.navigationBars.firstMatch.tap()
        let image = XCUIScreen.main.screenshot().image
        XCTAssertGreaterThan(image.size.width, image.size.height)
        capture(name: "details-landscape")
    }

    private func launch() -> XCUIApplication {
        continueAfterFailure = false
        XCUIDevice.shared.orientation = .portrait
        let app = XCUIApplication()
        app.launch()
        XCTAssertTrue(app.buttons["account.statement"].waitForExistence(timeout: 10))
        return app
    }

    private func openStatement(_ app: XCUIApplication) {
        app.buttons["account.statement"].tap()
        XCTAssertTrue(app.tables["statement.list"].cells["statement.transaction.demo-credit"].waitForExistence(timeout: 5))
        app.navigationBars.firstMatch.tap()
    }

    private func capture(name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
