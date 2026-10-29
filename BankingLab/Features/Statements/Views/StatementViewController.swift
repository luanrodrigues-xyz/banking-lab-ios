import UIKit

@MainActor
final class StatementViewController: UIViewController {
    private let viewModel: StatementViewModel
    private let statementView: StatementView
    private var initialTask: Task<Void, Never>?
    private var paginationTask: Task<Void, Never>?
    private var initialRequestID: UUID?
    private var paginationRequestID: UUID?
    private var isStopped = false

    init(viewModel: StatementViewModel, statementView: StatementView) {
        self.viewModel = viewModel
        self.statementView = statementView
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("Use init(viewModel:statementView:).")
    }

    deinit {
        initialTask?.cancel()
        paginationTask?.cancel()
    }

    override func loadView() {
        view = statementView
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "Extrato"
        guard !isStopped else { return }
        viewModel.onStateChange = { [weak self] state in
            self?.statementView.render(state)
        }
        statementView.onRetry = { [weak self] in self?.loadInitial() }
        statementView.onLoadMore = { [weak self] in self?.loadMore() }
        statementView.onSelectTransaction = { [weak self] id in
            self?.viewModel.selectTransaction(id: id)
        }
        statementView.render(viewModel.state)
        loadInitial()
    }

    func stop() {
        guard !isStopped else { return }
        isStopped = true
        initialRequestID = nil
        paginationRequestID = nil
        initialTask?.cancel()
        paginationTask?.cancel()
        initialTask = nil
        paginationTask = nil
        viewModel.onStateChange = nil
        statementView.onRetry = nil
        statementView.onLoadMore = nil
        statementView.onSelectTransaction = nil
        viewModel.cancel()
    }

    private func loadInitial() {
        guard !isStopped else { return }
        initialTask?.cancel()
        paginationTask?.cancel()
        paginationTask = nil
        paginationRequestID = nil
        viewModel.cancel()
        let requestID = UUID()
        initialRequestID = requestID
        initialTask = Task { [weak self, viewModel] in
            await viewModel.loadInitial()
            guard let self, self.initialRequestID == requestID else { return }
            self.initialTask = nil
            self.initialRequestID = nil
        }
    }

    private func loadMore() {
        guard !isStopped, paginationTask == nil else { return }
        let requestID = UUID()
        paginationRequestID = requestID
        paginationTask = Task { [weak self, viewModel] in
            await viewModel.loadMore()
            guard let self, self.paginationRequestID == requestID else { return }
            self.paginationTask = nil
            self.paginationRequestID = nil
        }
    }
}
