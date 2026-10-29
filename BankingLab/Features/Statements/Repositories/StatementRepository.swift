import Foundation

protocol StatementRepository: Sendable {
    func fetchPage(cursor: String?) async throws -> StatementPage
}

enum StatementRepositoryError: Error, Equatable {
    case emptyTransactionID(index: Int)
    case invalidDate(transactionID: String)
    case emptyCursor
    case repeatedCursor
}

struct DefaultStatementRepository: StatementRepository {
    private let service: any StatementService

    init(service: any StatementService) {
        self.service = service
    }

    func fetchPage(cursor: String?) async throws -> StatementPage {
        try Task.checkCancellation()
        try validateCursor(cursor)
        let dto = try await service.fetchPage(cursor: cursor)
        try Task.checkCancellation()
        try validateCursor(dto.nextCursor)
        if let cursor, cursor == dto.nextCursor {
            throw StatementRepositoryError.repeatedCursor
        }

        let dateParser = ISO8601DateFormatter()
        let items = try dto.items.enumerated().map { index, item in
            guard !item.id.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                throw StatementRepositoryError.emptyTransactionID(index: index)
            }
            guard let date = parseDate(item.occurredAt, using: dateParser) else {
                throw StatementRepositoryError.invalidDate(transactionID: item.id)
            }
            return StatementTransaction(
                id: item.id,
                occurredAt: date,
                description: item.description,
                amount: MonetaryAmount(cents: item.amountInCents)
            )
        }
        return StatementPage(items: items, nextCursor: dto.nextCursor)
    }

    private func validateCursor(_ cursor: String?) throws {
        if let cursor, cursor.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            throw StatementRepositoryError.emptyCursor
        }
    }

    private func parseDate(_ value: String, using parser: ISO8601DateFormatter) -> Date? {
        let pattern = #"[0-9]{4}-(0[1-9]|1[0-2])-(0[1-9]|[12][0-9]|3[01])T([01][0-9]|2[0-3]):[0-5][0-9]:[0-5][0-9](\.[0-9]+)?(Z|[+-]([01][0-9]|2[0-3]):[0-5][0-9])"#
        guard value.range(of: pattern, options: .regularExpression) == (value.startIndex..<value.endIndex) else {
            return nil
        }

        let parts = value.prefix(10).split(separator: "-").compactMap { Int($0) }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let components = DateComponents(year: parts[0], month: parts[1], day: parts[2])
        guard let day = calendar.date(from: components) else { return nil }
        let actual = calendar.dateComponents([.year, .month, .day], from: day)
        guard actual.year == components.year, actual.month == components.month,
              actual.day == components.day else { return nil }

        parser.formatOptions = value.contains(".")
            ? [.withInternetDateTime, .withFractionalSeconds]
            : [.withInternetDateTime]
        return parser.date(from: value)
    }
}
