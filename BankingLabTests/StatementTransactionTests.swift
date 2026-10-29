import Foundation
import XCTest
@testable import BankingLab

final class StatementTransactionTests: XCTestCase {
    func testPreservesSourceIdentityAndTransactionData() {
        let date = Date(timeIntervalSince1970: 1_700_000_000)
        let transaction = StatementTransaction(
            id: "transaction-42",
            occurredAt: date,
            description: "Transação de exemplo",
            amount: MonetaryAmount(cents: -12_345)
        )

        XCTAssertEqual(transaction.id, "transaction-42")
        XCTAssertEqual(transaction.occurredAt, date)
        XCTAssertEqual(transaction.description, "Transação de exemplo")
        XCTAssertEqual(transaction.amount.cents, -12_345)
    }

    func testUpdatedDataKeepsSameIdentity() {
        let original = StatementTransaction(
            id: "transaction-42",
            occurredAt: Date(timeIntervalSince1970: 1_700_000_000),
            description: "Descrição inicial",
            amount: MonetaryAmount(cents: 100)
        )
        let updated = StatementTransaction(
            id: original.id,
            occurredAt: Date(timeIntervalSince1970: 1_700_000_001),
            description: "Descrição atualizada",
            amount: MonetaryAmount(cents: 200)
        )

        XCTAssertEqual(original.id, updated.id)
        XCTAssertNotEqual(original, updated)
        XCTAssertEqual(original.amount.cents, 100)
        XCTAssertEqual(updated.amount.cents, 200)
    }
}
