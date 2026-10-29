import UIKit

@MainActor
struct StatementFactory {
    let repository: any StatementRepository
    let currencyCode: String
    let locale: Locale
    let timeZone: TimeZone

    func makeStatement(onSelect: @escaping @MainActor (StatementTransaction) -> Void) -> StatementViewController {
        let viewModel = StatementViewModel(repository: repository)
        viewModel.onSelectTransaction = onSelect
        let view = StatementView(currencyCode: currencyCode, locale: locale, timeZone: timeZone)
        return StatementViewController(viewModel: viewModel, statementView: view)
    }

    func makeDetails(transaction: StatementTransaction) -> StatementDetailsViewController {
        StatementDetailsViewController(transaction: transaction, currencyCode: currencyCode, locale: locale, timeZone: timeZone)
    }
}
