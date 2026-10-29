import UIKit

@MainActor
enum AppCompositionRoot {
    static func makeCoordinator() -> AppCoordinator {
        let locale = Locale(identifier: "pt_BR")
        let factory = StatementFactory(
            repository: DefaultStatementRepository(service: DemoStatementService()),
            currencyCode: "BRL",
            locale: locale,
            timeZone: .current
        )
        let account = AccountViewController(balance: MonetaryAmount(cents: 250_000), currencyCode: "BRL", locale: locale)
        return AppCoordinator(navigationController: UINavigationController(), account: account, statementFactory: factory)
    }
}
