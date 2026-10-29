import Foundation
import XCTest
@testable import BankingLab

final class StatementRepositoryTests: XCTestCase {
    func testMapsCompletePagePreservingOrderAndExactAmounts() async throws {
        let service = StubStatementService(page: StatementPageDTO(items: [
            item(id: "second", amount: .min), item(id: "first", amount: .max)
        ], nextCursor: "next-page"))

        let page = try await DefaultStatementRepository(service: service).fetchPage(cursor: nil)

        XCTAssertEqual(page.items.map(\.id), ["second", "first"])
        XCTAssertEqual(page.items.map(\.amount.cents), [.min, .max])
        XCTAssertEqual(page.items.first?.description, "Exemplo")
        XCTAssertEqual(page.items.first?.occurredAt, Date(timeIntervalSince1970: 0))
        XCTAssertEqual(page.nextCursor, "next-page")
        let cursors = await service.cursors
        XCTAssertEqual(cursors, [nil])
    }

    func testMapsEmptyFinalPage() async throws {
        let page = try await fetch(items: [], nextCursor: nil)

        XCTAssertEqual(page, StatementPage(items: [], nextCursor: nil))
    }

    func testEmptyIntermediatePagePreservesCursor() async throws {
        let page = try await fetch(items: [], nextCursor: "continue")

        XCTAssertTrue(page.items.isEmpty)
        XCTAssertEqual(page.nextCursor, "continue")
    }

    func testParsesFractionalSecondsAndExplicitOffset() async throws {
        let page = try await fetch(items: [
            item(id: "utc", date: "1970-01-01T00:00:00.125Z"),
            item(id: "offset", date: "1970-01-01T03:30:00.125+03:30"),
            item(id: "negative-offset", date: "1969-12-31T21:00:00-03:00")
        ])

        XCTAssertEqual(page.items[0].occurredAt.timeIntervalSince1970, 0.125, accuracy: 0.000_001)
        XCTAssertEqual(page.items[1].occurredAt, page.items[0].occurredAt)
        XCTAssertEqual(page.items[2].occurredAt, Date(timeIntervalSince1970: 0))
    }

    func testAcceptsValidLeapDay() async throws {
        let page = try await fetch(items: [item(date: "2024-02-29T00:00:00Z")])

        XCTAssertEqual(page.items.first?.occurredAt, Date(timeIntervalSince1970: 1_709_164_800))
    }

    func testRejectsEntirePageWhenAnIdentityIsBlank() async throws {
        for id in ["", " \n\t"] {
            do {
                _ = try await fetch(items: [item(id: "valid"), item(id: id)])
                XCTFail("Esperava rejeição da página inteira")
            } catch {
                XCTAssertEqual(error as? StatementRepositoryError, .emptyTransactionID(index: 1))
            }
        }
    }

    func testRejectsInvalidOrIncompleteDates() async throws {
        for date in [
            "", "invalid-date", "2026-02-30T00:00:00Z", "2025-02-29T00:00:00Z",
            "2026-13-01T00:00:00Z", "2026-01-01T24:00:00Z", "2026-01-01T00:60:00Z",
            "2026-01-01T00:00:60Z", "2026-01-01", "2026-01-01T00:00:00",
            "2026-01-01T00:00:00Ztrailing", "2026-01-01T00:00:00Z\n",
            "2026-01-01T00:00:00+99:00"
        ] {
            do {
                _ = try await fetch(items: [item(date: date)])
                XCTFail("Esperava rejeição da data: \(date)")
            } catch {
                XCTAssertEqual(error as? StatementRepositoryError, .invalidDate(transactionID: "transaction-42"))
            }
        }
    }

    func testRejectsBlankRequestedCursorBeforeCallingService() async throws {
        for cursor in ["", " \n\t"] {
            let service = StubStatementService(page: StatementPageDTO(items: [], nextCursor: nil))
            do {
                _ = try await DefaultStatementRepository(service: service).fetchPage(cursor: cursor)
                XCTFail("Esperava rejeição do cursor")
            } catch {
                XCTAssertEqual(error as? StatementRepositoryError, .emptyCursor)
            }
            let cursors = await service.cursors
            XCTAssertTrue(cursors.isEmpty)
        }
    }

    func testRejectsBlankNextCursor() async throws {
        for cursor in ["", " \n\t"] {
            do {
                _ = try await fetch(items: [item()], nextCursor: cursor)
                XCTFail("Esperava rejeição do cursor da resposta")
            } catch {
                XCTAssertEqual(error as? StatementRepositoryError, .emptyCursor)
            }
        }
    }

    func testRejectsNextCursorEqualToRequestedCursor() async throws {
        let service = StubStatementService(page: StatementPageDTO(items: [item()], nextCursor: "same"))
        do {
            _ = try await DefaultStatementRepository(service: service).fetchPage(cursor: "same")
            XCTFail("Esperava rejeição de cursor sem avanço")
        } catch {
            XCTAssertEqual(error as? StatementRepositoryError, .repeatedCursor)
        }
    }

    func testPreservesOpaqueIdentifiersAndCursorsWithoutTrimming() async throws {
        let service = StubStatementService(page: StatementPageDTO(items: [item(id: " opaque/id ")], nextCursor: " next/+?= "))
        let page = try await DefaultStatementRepository(service: service).fetchPage(cursor: " previous/+?= ")

        XCTAssertEqual(page.items.first?.id, " opaque/id ")
        XCTAssertEqual(page.nextCursor, " next/+?= ")
        let cursors = await service.cursors
        XCTAssertEqual(cursors, [" previous/+?= "])
    }

    func testPreservesRepeatedIDsForPresentationMerge() async throws {
        let page = try await fetch(items: [item(amount: 100), item(amount: 200)])

        XCTAssertEqual(page.items.map(\.id), ["transaction-42", "transaction-42"])
        XCTAssertEqual(page.items.map(\.amount.cents), [100, 200])
    }

    func testAllowsEmptyDescriptionAndZeroAmount() async throws {
        let dto = StatementTransactionDTO(id: "a", occurredAt: "1970-01-01T00:00:00Z", description: "", amountInCents: 0)
        let page = try await fetch(items: [dto])

        XCTAssertEqual(page.items.first?.description, "")
        XCTAssertEqual(page.items.first?.amount.cents, 0)
    }

    func testPreservesServiceError() async {
        let service = StubStatementService(error: StatementServiceError.httpStatus(503))
        do {
            _ = try await DefaultStatementRepository(service: service).fetchPage(cursor: nil)
            XCTFail("Esperava o erro do Service")
        } catch {
            XCTAssertEqual(error as? StatementServiceError, .httpStatus(503))
        }
    }

    @MainActor
    func testAlreadyCancelledTaskDoesNotCallService() async {
        let service = StubStatementService(page: StatementPageDTO(items: [], nextCursor: nil))
        let repository = DefaultStatementRepository(service: service)
        let task = Task { try await repository.fetchPage(cursor: nil) }
        task.cancel()

        do {
            _ = try await task.value
            XCTFail("Esperava cancelamento")
        } catch {
            XCTAssertTrue(error is CancellationError)
        }
        let cursors = await service.cursors
        XCTAssertTrue(cursors.isEmpty)
    }

    func testDiscardsPageWhenServiceIgnoresCancellation() async throws {
        let service = StubStatementService(page: StatementPageDTO(items: [item()], nextCursor: nil), holdResponse: true)
        let repository = DefaultStatementRepository(service: service)
        let task = Task { try await repository.fetchPage(cursor: nil) }
        await service.waitUntilRequested()
        task.cancel()
        await service.releaseResponse()

        do {
            _ = try await task.value
            XCTFail("Esperava descarte da página após cancelamento")
        } catch {
            XCTAssertTrue(error is CancellationError)
        }
    }

    private func item(id: String = "transaction-42", date: String = "1970-01-01T00:00:00Z", amount: Int64 = 100) -> StatementTransactionDTO {
        StatementTransactionDTO(id: id, occurredAt: date, description: "Exemplo", amountInCents: amount)
    }

    private func fetch(items: [StatementTransactionDTO], nextCursor: String? = nil) async throws -> StatementPage {
        let service = StubStatementService(page: StatementPageDTO(items: items, nextCursor: nextCursor))
        return try await DefaultStatementRepository(service: service).fetchPage(cursor: nil)
    }
}

private actor StubStatementService: StatementService {
    private let result: Result<StatementPageDTO, any Error>
    private let holdResponse: Bool
    private(set) var cursors: [String?] = []
    private var responseContinuation: CheckedContinuation<StatementPageDTO, any Error>?
    private var requestContinuation: CheckedContinuation<Void, Never>?

    init(page: StatementPageDTO, holdResponse: Bool = false) {
        result = .success(page)
        self.holdResponse = holdResponse
    }

    init(error: any Error) {
        result = .failure(error)
        holdResponse = false
    }

    func fetchPage(cursor: String?) async throws -> StatementPageDTO {
        cursors.append(cursor)
        requestContinuation?.resume()
        requestContinuation = nil
        if holdResponse {
            return try await withCheckedThrowingContinuation { responseContinuation = $0 }
        }
        return try result.get()
    }

    func waitUntilRequested() async {
        if cursors.isEmpty {
            await withCheckedContinuation { requestContinuation = $0 }
        }
    }

    func releaseResponse() {
        responseContinuation?.resume(with: result)
        responseContinuation = nil
    }
}
