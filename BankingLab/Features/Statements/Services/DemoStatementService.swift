import Foundation

enum DemoStatementServiceError: Error { case unknownCursor }

actor DemoStatementService: StatementService {
    func fetchPage(cursor: String?) async throws -> StatementPageDTO {
        try Task.checkCancellation()
        switch cursor {
        case nil:
            return StatementPageDTO(items: [
                item("demo-credit", "2026-10-29T12:00:00Z", "Crédito de demonstração", 350_000),
                item("demo-market", "2026-10-28T18:00:00Z", "Mercado", -8_940),
                item("demo-transport", "2026-10-28T12:00:00Z", "Transporte", -1_250)
            ], nextCursor: "demo-page-2")
        case "demo-page-2":
            return StatementPageDTO(items: [
                item("demo-market", "2026-10-28T18:00:00Z", "Mercado — valor atualizado", -9_235),
                item("demo-coffee", "2026-10-27T15:00:00Z", "Café", -1_850),
                item("demo-book", "2026-10-26T14:00:00Z", "Livraria", -6_490)
            ], nextCursor: nil)
        default:
            throw DemoStatementServiceError.unknownCursor
        }
    }

    private func item(_ id: String, _ date: String, _ description: String, _ cents: Int64) -> StatementTransactionDTO {
        StatementTransactionDTO(id: id, occurredAt: date, description: description, amountInCents: cents)
    }
}
