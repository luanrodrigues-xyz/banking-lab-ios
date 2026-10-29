import Foundation

enum StatementPaginationState: Equatable, Sendable {
    case idle
    case loading
    case failed
}

enum StatementViewState: Equatable, Sendable {
    case idle
    case loading
    case loaded(StatementPage, pagination: StatementPaginationState = .idle)
    case empty
    case failed
}

@MainActor
final class StatementViewModel {
    private(set) var state: StatementViewState = .idle {
        didSet { onStateChange?(state) }
    }
    var onStateChange: (@MainActor (StatementViewState) -> Void)?
    var onSelectTransaction: (@MainActor (StatementTransaction) -> Void)?

    private let repository: any StatementRepository
    private var generation = UUID()
    private var consumedCursors: Set<String> = []

    init(repository: any StatementRepository) {
        self.repository = repository
    }

    func loadInitial() async {
        guard !Task.isCancelled else { return }
        let requestGeneration = UUID()
        generation = requestGeneration
        consumedCursors = []
        state = .loading
        guard requestGeneration == generation else { return }

        do {
            try Task.checkCancellation()
            let page = try await repository.fetchPage(cursor: nil)
            guard requestGeneration == generation else { return }
            if Task.isCancelled {
                state = .idle
                return
            }
            let merged = StatementPage(items: merge([], with: page.items), nextCursor: page.nextCursor)
            state = merged.items.isEmpty && merged.nextCursor == nil ? .empty : .loaded(merged)
        } catch {
            guard requestGeneration == generation else { return }
            let cancelled = Task.isCancelled || error is CancellationError
                || (error as? URLError)?.code == .cancelled
            state = cancelled ? .idle : .failed
        }
    }

    func cancel() {
        generation = UUID()
        if state == .loading {
            state = .idle
        } else if case .loaded(let page, .loading) = state {
            state = .loaded(page)
        }
    }

    func selectTransaction(id: String) {
        guard case .loaded(let page, _) = state,
              let transaction = page.items.first(where: { $0.id == id }) else { return }
        onSelectTransaction?(transaction)
    }

    func loadMore() async {
        guard !Task.isCancelled,
              case .loaded(let previous, let pagination) = state,
              pagination != .loading, let cursor = previous.nextCursor else { return }
        let requestGeneration = generation
        state = .loaded(previous, pagination: .loading)
        guard requestGeneration == generation else { return }

        do {
            try Task.checkCancellation()
            let next = try await repository.fetchPage(cursor: cursor)
            guard requestGeneration == generation else { return }
            guard !Task.isCancelled else {
                state = .loaded(previous)
                return
            }
            if let nextCursor = next.nextCursor,
               nextCursor == cursor || consumedCursors.contains(nextCursor) {
                state = .loaded(previous, pagination: .failed)
                return
            }
            consumedCursors.insert(cursor)
            let page = StatementPage(items: merge(previous.items, with: next.items), nextCursor: next.nextCursor)
            state = page.items.isEmpty && page.nextCursor == nil ? .empty : .loaded(page)
        } catch {
            guard requestGeneration == generation else { return }
            let cancelled = Task.isCancelled || error is CancellationError
                || (error as? URLError)?.code == .cancelled
            state = .loaded(previous, pagination: cancelled ? .idle : .failed)
        }
    }

    private func merge(_ current: [StatementTransaction], with incoming: [StatementTransaction]) -> [StatementTransaction] {
        var items = current
        var indices = Dictionary(uniqueKeysWithValues: current.enumerated().map { ($0.element.id, $0.offset) })
        for item in incoming {
            if let index = indices[item.id] {
                items[index] = item
            } else {
                indices[item.id] = items.count
                items.append(item)
            }
        }
        return items
    }
}
