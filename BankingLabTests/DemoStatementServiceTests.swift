import Foundation
import XCTest
@testable import BankingLab

final class DemoStatementServiceTests: XCTestCase {
    func testDemoPagesPassThroughRealRepository() async throws {
        let repository = DefaultStatementRepository(service: DemoStatementService())
        let first = try await repository.fetchPage(cursor: nil)
        let nextCursor = try XCTUnwrap(first.nextCursor)
        let second = try await repository.fetchPage(cursor: nextCursor)

        XCTAssertEqual(first.items.count, 3)
        XCTAssertEqual(second.items.count, 3)
        XCTAssertNil(second.nextCursor)
        XCTAssertEqual(first.items[0].amount.cents, 350_000)
        XCTAssertEqual(second.items[0].id, first.items[1].id)
        XCTAssertEqual(second.items[0].amount.cents, -9_235)
    }

    func testDemoIsDeterministicWhenFlowReopens() async throws {
        let service = DemoStatementService()
        let first = try await service.fetchPage(cursor: nil)
        _ = try await service.fetchPage(cursor: first.nextCursor)
        let reopened = try await service.fetchPage(cursor: nil)

        XCTAssertEqual(first, reopened)
    }

    func testUnknownCursorFails() async {
        do {
            _ = try await DemoStatementService().fetchPage(cursor: "unknown")
            XCTFail("Esperava rejeição de cursor desconhecido")
        } catch {
            XCTAssertTrue(error is DemoStatementServiceError)
        }
    }

    @MainActor
    func testDemoHonorsCancellation() async {
        let service = DemoStatementService()
        let task = Task { try await service.fetchPage(cursor: nil) }
        task.cancel()
        do {
            _ = try await task.value
            XCTFail("Esperava cancelamento")
        } catch {
            XCTAssertTrue(error is CancellationError)
        }
    }
}
