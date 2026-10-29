import Foundation

struct StatementTransaction: Identifiable, Equatable, Sendable {
    let id: String
    let occurredAt: Date
    let description: String
    let amount: MonetaryAmount
}
