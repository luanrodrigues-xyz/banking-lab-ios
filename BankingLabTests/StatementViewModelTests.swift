import Foundation
import XCTest
@testable import BankingLab

@MainActor
final class StatementViewModelTests: XCTestCase {
    func testInitialLoadingPublishesContentAndCursor() async {
        let repository = ControlledStatementRepository()
        let viewModel = StatementViewModel(repository: repository)
        var states: [StatementViewState] = []
        viewModel.onStateChange = { states.append($0) }
        XCTAssertEqual(viewModel.state, .idle)

        let task = Task { await viewModel.loadInitial() }
        await repository.waitForRequests(1)
        XCTAssertEqual(viewModel.state, .loading)
        let expected = page(id: "a", cursor: "next")
        await repository.complete(0, with: .success(expected))
        await task.value

        XCTAssertEqual(viewModel.state, .loaded(expected))
        XCTAssertEqual(states, [.loading, .loaded(expected)])
        let cursors = await repository.cursors
        XCTAssertEqual(cursors, [nil])
    }

    func testEmptyFinalPagePublishesEmptyState() async {
        let repository = ControlledStatementRepository()
        let viewModel = StatementViewModel(repository: repository)
        let task = Task { await viewModel.loadInitial() }
        await repository.waitForRequests(1)
        await repository.complete(0, with: .success(StatementPage(items: [], nextCursor: nil)))
        await task.value

        XCTAssertEqual(viewModel.state, .empty)
    }

    func testEmptyIntermediatePageKeepsContinuation() async {
        let repository = ControlledStatementRepository()
        let viewModel = StatementViewModel(repository: repository)
        let task = Task { await viewModel.loadInitial() }
        await repository.waitForRequests(1)
        let expected = StatementPage(items: [], nextCursor: "continue")
        await repository.complete(0, with: .success(expected))
        await task.value

        XCTAssertEqual(viewModel.state, .loaded(expected))
    }

    func testInitialFailureCanBeRetried() async {
        let repository = ControlledStatementRepository()
        let viewModel = StatementViewModel(repository: repository)
        let first = Task { await viewModel.loadInitial() }
        await repository.waitForRequests(1)
        await repository.complete(0, with: .failure(URLError(.notConnectedToInternet)))
        await first.value
        XCTAssertEqual(viewModel.state, .failed)

        let retry = Task { await viewModel.loadInitial() }
        await repository.waitForRequests(2)
        XCTAssertEqual(viewModel.state, .loading)
        let expected = page(id: "retry")
        await repository.complete(1, with: .success(expected))
        await retry.value

        XCTAssertEqual(viewModel.state, .loaded(expected))
    }

    func testOldSuccessCannotReplaceNewSuccess() async {
        let repository = ControlledStatementRepository()
        let viewModel = StatementViewModel(repository: repository)
        let old = Task { await viewModel.loadInitial() }
        await repository.waitForRequests(1)
        let current = Task { await viewModel.loadInitial() }
        await repository.waitForRequests(2)
        let expected = page(id: "new")
        await repository.complete(1, with: .success(expected))
        await current.value
        await repository.complete(0, with: .success(page(id: "old")))
        await old.value

        XCTAssertEqual(viewModel.state, .loaded(expected))
    }

    func testOldFailureCannotReplaceNewSuccess() async {
        let repository = ControlledStatementRepository()
        let viewModel = StatementViewModel(repository: repository)
        let old = Task { await viewModel.loadInitial() }
        await repository.waitForRequests(1)
        let current = Task { await viewModel.loadInitial() }
        await repository.waitForRequests(2)
        let expected = page(id: "new")
        await repository.complete(1, with: .success(expected))
        await current.value
        await repository.complete(0, with: .failure(URLError(.timedOut)))
        await old.value

        XCTAssertEqual(viewModel.state, .loaded(expected))
    }

    func testCancelDiscardsResponseFromUncooperativeRepository() async {
        let repository = ControlledStatementRepository()
        let viewModel = StatementViewModel(repository: repository)
        let task = Task { await viewModel.loadInitial() }
        await repository.waitForRequests(1)
        viewModel.cancel()
        XCTAssertEqual(viewModel.state, .idle)
        await repository.complete(0, with: .success(page(id: "late")))
        await task.value

        XCTAssertEqual(viewModel.state, .idle)
    }

    func testTaskCancellationDiscardsReturnedPage() async {
        let repository = ControlledStatementRepository()
        let viewModel = StatementViewModel(repository: repository)
        let task = Task { await viewModel.loadInitial() }
        await repository.waitForRequests(1)
        task.cancel()
        await repository.complete(0, with: .success(page(id: "late")))
        await task.value

        XCTAssertEqual(viewModel.state, .idle)
    }

    func testTransportCancellationDoesNotPublishFailure() async {
        let repository = ControlledStatementRepository()
        let viewModel = StatementViewModel(repository: repository)
        let task = Task { await viewModel.loadInitial() }
        await repository.waitForRequests(1)
        await repository.complete(0, with: .failure(URLError(.cancelled)))
        await task.value

        XCTAssertEqual(viewModel.state, .idle)
    }

    func testAlreadyCancelledTaskLeavesStateUntouched() async {
        let repository = ControlledStatementRepository()
        let viewModel = StatementViewModel(repository: repository)
        let task = Task { await viewModel.loadInitial() }
        task.cancel()
        await task.value

        XCTAssertEqual(viewModel.state, .idle)
        let cursors = await repository.cursors
        XCTAssertTrue(cursors.isEmpty)
    }

    func testCancelPreservesAlreadyLoadedContent() async {
        let repository = ControlledStatementRepository()
        let viewModel = StatementViewModel(repository: repository)
        let task = Task { await viewModel.loadInitial() }
        await repository.waitForRequests(1)
        let expected = page(id: "a")
        await repository.complete(0, with: .success(expected))
        await task.value

        viewModel.cancel()

        XCTAssertEqual(viewModel.state, .loaded(expected))
    }

    func testPaginationFailurePreservesPageAndRetriesSameCursor() async {
        let repository = ControlledStatementRepository()
        let viewModel = StatementViewModel(repository: repository)
        let initialPage = page(id: "a", cursor: "page-2")
        await load(viewModel, repository: repository, page: initialPage)
        let more = Task { await viewModel.loadMore() }
        await repository.waitForRequests(2)
        XCTAssertEqual(viewModel.state, .loaded(initialPage, pagination: .loading))
        await repository.complete(1, with: .failure(URLError(.timedOut)))
        await more.value
        XCTAssertEqual(viewModel.state, .loaded(initialPage, pagination: .failed))

        let retry = Task { await viewModel.loadMore() }
        await repository.waitForRequests(3)
        let nextPage = page(id: "b")
        await repository.complete(2, with: .success(nextPage))
        await retry.value

        XCTAssertEqual(viewModel.state, .loaded(StatementPage(items: initialPage.items + nextPage.items, nextCursor: nil)))
        let cursors = await repository.cursors
        XCTAssertEqual(cursors, [nil, "page-2", "page-2"])
    }

    func testRapidPaginationRequestsProduceOnePageRequest() async {
        let repository = ControlledStatementRepository()
        let viewModel = StatementViewModel(repository: repository)
        await load(viewModel, repository: repository, page: page(id: "a", cursor: "page-2"))
        let first = Task { await viewModel.loadMore() }
        await repository.waitForRequests(2)
        await viewModel.loadMore()
        let cursors = await repository.cursors
        XCTAssertEqual(cursors, [nil, "page-2"])
        await repository.complete(1, with: .success(page(id: "b")))
        await first.value
    }

    func testPaginationUpdatesRepeatedIDWithoutMovingItsPosition() async {
        let repository = ControlledStatementRepository()
        let viewModel = StatementViewModel(repository: repository)
        let first = page(id: "a", cursor: "page-2")
        await load(viewModel, repository: repository, page: first)
        let updated = StatementTransaction(id: "a", occurredAt: Date(timeIntervalSince1970: 10), description: "Atualizada", amount: MonetaryAmount(cents: 999))
        let next = StatementPage(items: page(id: "b").items + [updated, updated], nextCursor: nil)
        let task = Task { await viewModel.loadMore() }
        await repository.waitForRequests(2)
        await repository.complete(1, with: .success(next))
        await task.value

        XCTAssertEqual(viewModel.state, .loaded(StatementPage(items: [updated] + page(id: "b").items, nextCursor: nil)))
    }

    func testInitialPageMergesRepeatedIDs() async {
        let repository = ControlledStatementRepository()
        let viewModel = StatementViewModel(repository: repository)
        let original = page(id: "a").items[0]
        let updated = StatementTransaction(id: "a", occurredAt: original.occurredAt, description: "Atualizada", amount: MonetaryAmount(cents: 200))
        await load(viewModel, repository: repository, page: StatementPage(items: [original, updated], nextCursor: nil))

        XCTAssertEqual(viewModel.state, .loaded(StatementPage(items: [updated], nextCursor: nil)))
    }

    func testFinalPagePreventsFurtherRequests() async {
        let repository = ControlledStatementRepository()
        let viewModel = StatementViewModel(repository: repository)
        await load(viewModel, repository: repository, page: page(id: "a"))
        await viewModel.loadMore()

        let cursors = await repository.cursors
        XCTAssertEqual(cursors, [nil])
    }

    func testEmptyIntermediatePageCanContinueLoading() async {
        let repository = ControlledStatementRepository()
        let viewModel = StatementViewModel(repository: repository)
        await load(viewModel, repository: repository, page: StatementPage(items: [], nextCursor: "next"))
        let task = Task { await viewModel.loadMore() }
        await repository.waitForRequests(2)
        let expected = page(id: "a")
        await repository.complete(1, with: .success(expected))
        await task.value

        XCTAssertEqual(viewModel.state, .loaded(expected))
    }

    func testCursorCycleFailsWithoutApplyingPage() async {
        let repository = ControlledStatementRepository()
        let viewModel = StatementViewModel(repository: repository)
        let first = page(id: "a", cursor: "one")
        await load(viewModel, repository: repository, page: first)
        let more = Task { await viewModel.loadMore() }
        await repository.waitForRequests(2)
        let second = page(id: "b", cursor: "two")
        await repository.complete(1, with: .success(second))
        await more.value
        let cycle = Task { await viewModel.loadMore() }
        await repository.waitForRequests(3)
        await repository.complete(2, with: .success(page(id: "ignored", cursor: "one")))
        await cycle.value

        XCTAssertEqual(viewModel.state, .loaded(StatementPage(items: first.items + second.items, nextCursor: "two"), pagination: .failed))
    }

    func testCancelledPaginationPreservesContentAndDiscardsLateResult() async {
        let repository = ControlledStatementRepository()
        let viewModel = StatementViewModel(repository: repository)
        let initial = page(id: "a", cursor: "next")
        await load(viewModel, repository: repository, page: initial)
        let more = Task { await viewModel.loadMore() }
        await repository.waitForRequests(2)
        viewModel.cancel()
        await repository.complete(1, with: .success(page(id: "late")))
        await more.value

        XCTAssertEqual(viewModel.state, .loaded(initial))
    }

    func testReloadDiscardsOldPaginationFailure() async {
        let repository = ControlledStatementRepository()
        let viewModel = StatementViewModel(repository: repository)
        await load(viewModel, repository: repository, page: page(id: "a", cursor: "next"))
        let more = Task { await viewModel.loadMore() }
        await repository.waitForRequests(2)
        let reload = Task { await viewModel.loadInitial() }
        await repository.waitForRequests(3)
        let expected = page(id: "new")
        await repository.complete(2, with: .success(expected))
        await reload.value
        await repository.complete(1, with: .failure(URLError(.timedOut)))
        await more.value

        XCTAssertEqual(viewModel.state, .loaded(expected))
    }

    func testOldSuccessDoesNotEndNewLoadingState() async {
        let repository = ControlledStatementRepository()
        let viewModel = StatementViewModel(repository: repository)
        let old = Task { await viewModel.loadInitial() }
        await repository.waitForRequests(1)
        let current = Task { await viewModel.loadInitial() }
        await repository.waitForRequests(2)
        await repository.complete(0, with: .success(page(id: "old")))
        await old.value
        XCTAssertEqual(viewModel.state, .loading)
        let expected = page(id: "new")
        await repository.complete(1, with: .success(expected))
        await current.value
        XCTAssertEqual(viewModel.state, .loaded(expected))
    }

    func testOldFailureDoesNotEndNewLoadingState() async {
        let repository = ControlledStatementRepository()
        let viewModel = StatementViewModel(repository: repository)
        let old = Task { await viewModel.loadInitial() }
        await repository.waitForRequests(1)
        let current = Task { await viewModel.loadInitial() }
        await repository.waitForRequests(2)
        await repository.complete(0, with: .failure(URLError(.timedOut)))
        await old.value
        XCTAssertEqual(viewModel.state, .loading)
        await repository.complete(1, with: .success(StatementPage(items: [], nextCursor: nil)))
        await current.value
        XCTAssertEqual(viewModel.state, .empty)
    }

    func testLateErrorAfterExplicitCancelDoesNotPublishFailure() async {
        let repository = ControlledStatementRepository()
        let viewModel = StatementViewModel(repository: repository)
        let task = Task { await viewModel.loadInitial() }
        await repository.waitForRequests(1)
        viewModel.cancel()
        await repository.complete(0, with: .failure(URLError(.timedOut)))
        await task.value
        XCTAssertEqual(viewModel.state, .idle)
    }

    func testOldCancellationCannotResetNewContent() async {
        let repository = ControlledStatementRepository()
        let viewModel = StatementViewModel(repository: repository)
        let old = Task { await viewModel.loadInitial() }
        await repository.waitForRequests(1)
        let current = Task { await viewModel.loadInitial() }
        await repository.waitForRequests(2)
        let expected = page(id: "new")
        await repository.complete(1, with: .success(expected))
        await current.value
        await repository.complete(0, with: .failure(CancellationError()))
        await old.value
        XCTAssertEqual(viewModel.state, .loaded(expected))
    }

    func testReloadDiscardsOldPaginationSuccess() async {
        let repository = ControlledStatementRepository()
        let viewModel = StatementViewModel(repository: repository)
        await load(viewModel, repository: repository, page: page(id: "a", cursor: "next"))
        let more = Task { await viewModel.loadMore() }
        await repository.waitForRequests(2)
        let reload = Task { await viewModel.loadInitial() }
        await repository.waitForRequests(3)
        let expected = page(id: "new")
        await repository.complete(2, with: .success(expected))
        await reload.value
        await repository.complete(1, with: .success(page(id: "old-page")))
        await more.value
        XCTAssertEqual(viewModel.state, .loaded(expected))
    }

    func testCancelledPaginationTaskDoesNotPublishError() async {
        let repository = ControlledStatementRepository()
        let viewModel = StatementViewModel(repository: repository)
        let expected = page(id: "a", cursor: "next")
        await load(viewModel, repository: repository, page: expected)
        let task = Task { await viewModel.loadMore() }
        await repository.waitForRequests(2)
        task.cancel()
        await repository.complete(1, with: .failure(URLError(.timedOut)))
        await task.value
        XCTAssertEqual(viewModel.state, .loaded(expected))
    }

    func testObserverCanCancelBeforeRepositoryStarts() async {
        let repository = ControlledStatementRepository()
        let viewModel = StatementViewModel(repository: repository)
        viewModel.onStateChange = { [weak viewModel] state in
            if state == .loading { viewModel?.cancel() }
        }
        await viewModel.loadInitial()
        XCTAssertEqual(viewModel.state, .idle)
        let cursors = await repository.cursors
        XCTAssertTrue(cursors.isEmpty)
    }

    func testSelectionUsesLatestTransactionAfterMerge() async {
        let repository = ControlledStatementRepository()
        let viewModel = StatementViewModel(repository: repository)
        await load(viewModel, repository: repository, page: page(id: "a", cursor: "next"))
        let updated = StatementTransaction(id: "a", occurredAt: Date(timeIntervalSince1970: 10), description: "Atualizada", amount: MonetaryAmount(cents: 999))
        let task = Task { await viewModel.loadMore() }
        await repository.waitForRequests(2)
        await repository.complete(1, with: .success(StatementPage(items: [updated], nextCursor: nil)))
        await task.value
        var selected: StatementTransaction?
        viewModel.onSelectTransaction = { selected = $0 }

        viewModel.selectTransaction(id: "a")

        XCTAssertEqual(selected, updated)
    }

    func testSelectionIgnoresUnknownID() async {
        let repository = ControlledStatementRepository()
        let viewModel = StatementViewModel(repository: repository)
        await load(viewModel, repository: repository, page: page(id: "a"))
        var selected: StatementTransaction?
        viewModel.onSelectTransaction = { selected = $0 }

        viewModel.selectTransaction(id: "unknown")

        XCTAssertNil(selected)
    }

    func testSelectionWithoutLoadedContentIsIgnored() async {
        let repository = ControlledStatementRepository()
        let viewModel = StatementViewModel(repository: repository)
        var selected: StatementTransaction?
        viewModel.onSelectTransaction = { selected = $0 }
        viewModel.selectTransaction(id: "a")
        let task = Task { await viewModel.loadInitial() }
        await repository.waitForRequests(1)
        viewModel.selectTransaction(id: "a")
        await repository.complete(0, with: .failure(URLError(.timedOut)))
        await task.value
        viewModel.selectTransaction(id: "a")

        XCTAssertNil(selected)
    }

    private func load(_ viewModel: StatementViewModel, repository: ControlledStatementRepository, page: StatementPage) async {
        let task = Task { await viewModel.loadInitial() }
        await repository.waitForRequests(1)
        await repository.complete(0, with: .success(page))
        await task.value
    }

    private func page(id: String, cursor: String? = nil) -> StatementPage {
        StatementPage(items: [StatementTransaction(
            id: id,
            occurredAt: Date(timeIntervalSince1970: 0),
            description: "Exemplo",
            amount: MonetaryAmount(cents: 100)
        )], nextCursor: cursor)
    }
}

private actor ControlledStatementRepository: StatementRepository {
    private(set) var cursors: [String?] = []
    private var continuations: [Int: CheckedContinuation<StatementPage, any Error>] = [:]
    private var waiters: [(Int, CheckedContinuation<Void, Never>)] = []

    func fetchPage(cursor: String?) async throws -> StatementPage {
        let index = cursors.count
        cursors.append(cursor)
        return try await withCheckedThrowingContinuation { continuation in
            continuations[index] = continuation
            let ready = waiters.filter { $0.0 <= cursors.count }
            waiters.removeAll { $0.0 <= cursors.count }
            ready.forEach { $0.1.resume() }
        }
    }

    func waitForRequests(_ count: Int) async {
        if cursors.count < count {
            await withCheckedContinuation { waiters.append((count, $0)) }
        }
    }

    func complete(_ index: Int, with result: Result<StatementPage, any Error>) {
        continuations.removeValue(forKey: index)?.resume(with: result)
    }
}
