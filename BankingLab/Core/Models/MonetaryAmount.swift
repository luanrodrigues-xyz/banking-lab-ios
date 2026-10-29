import Foundation

struct MonetaryAmount: Equatable, Sendable {
    let cents: Int64

    var decimalValue: Decimal {
        Decimal(cents) / 100
    }

    func formatted(currencyCode: String, locale: Locale) -> String {
        decimalValue.formatted(.currency(code: currencyCode).locale(locale))
    }
}
