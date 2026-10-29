import Foundation

struct StatementPageDTO: Decodable, Equatable, Sendable {
    let items: [StatementTransactionDTO]
    let nextCursor: String?
}

struct StatementTransactionDTO: Decodable, Equatable, Sendable {
    let id: String
    let occurredAt: String
    let description: String
    let amountInCents: Int64
}
