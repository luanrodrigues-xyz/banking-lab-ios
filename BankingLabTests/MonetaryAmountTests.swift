import Foundation
import XCTest
@testable import BankingLab

final class MonetaryAmountTests: XCTestCase {
    func testConvertsCentsWithoutDiscardingFraction() throws {
        XCTAssertEqual(MonetaryAmount(cents: 123_456).decimalValue, try decimal("1234.56"))
        XCTAssertEqual(MonetaryAmount(cents: 1).decimalValue, try decimal("0.01"))
    }

    func testConvertsZero() {
        XCTAssertEqual(MonetaryAmount(cents: 0).decimalValue, .zero)
    }

    func testConvertsNegativeCents() throws {
        XCTAssertEqual(MonetaryAmount(cents: -123).decimalValue, try decimal("-1.23"))
        XCTAssertEqual(MonetaryAmount(cents: -1).decimalValue, try decimal("-0.01"))
    }

    func testPreservesPrecisionAtInt64Limits() throws {
        XCTAssertEqual(MonetaryAmount(cents: .max).decimalValue, try decimal("92233720368547758.07"))
        XCTAssertEqual(MonetaryAmount(cents: .min).decimalValue, try decimal("-92233720368547758.08"))
    }

    func testFormatsPositiveAmount() {
        XCTAssertEqual(format(123_456), "$1,234.56")
    }

    func testFormatsZeroWithFractionDigits() {
        XCTAssertEqual(format(0), "$0.00")
    }

    func testFormatsNegativeAmount() {
        XCTAssertEqual(format(-123), "-$1.23")
    }

    func testFormatsSingleCent() {
        XCTAssertEqual(format(1), "$0.01")
    }

    func testFormatsInt64LimitsWithoutLosingCents() {
        XCTAssertEqual(format(.max), "$92,233,720,368,547,758.07")
        XCTAssertEqual(format(.min), "-$92,233,720,368,547,758.08")
    }

    func testUsesSuppliedCurrencyAndLocale() {
        let amount = MonetaryAmount(cents: 123_456)

        XCTAssertEqual(
            amount.formatted(currencyCode: "BRL", locale: Locale(identifier: "pt_BR")),
            "R$\u{00A0}1.234,56"
        )
        XCTAssertEqual(
            amount.formatted(currencyCode: "EUR", locale: Locale(identifier: "en_US")),
            "€1,234.56"
        )
    }

    private func format(_ cents: Int64) -> String {
        MonetaryAmount(cents: cents).formatted(currencyCode: "USD", locale: Locale(identifier: "en_US"))
    }

    private func decimal(_ value: String) throws -> Decimal {
        try XCTUnwrap(Decimal(string: value, locale: Locale(identifier: "en_US_POSIX")))
    }
}
