import UIKit

@MainActor
final class StatementView: UIView, UITableViewDelegate {
    var onRetry: (@MainActor () -> Void)?
    var onLoadMore: (@MainActor () -> Void)?
    var onSelectTransaction: (@MainActor (String) -> Void)?

    private enum Section: Hashable { case transactions }

    private let tableView = UITableView(frame: .zero, style: .plain)
    private let statusView = UIView()
    private let statusLabel = UILabel()
    private let initialSpinner = UIActivityIndicatorView(style: .large)
    private let retryButton = PrimaryButton(title: "Tentar novamente", accessibilityIdentifier: "statement.retry")
    private let footer = UIStackView()
    private let footerLabel = UILabel()
    private let paginationSpinner = UIActivityIndicatorView(style: .medium)
    private let loadMoreButton = PrimaryButton(title: "Carregar mais", accessibilityIdentifier: "statement.load-more")
    private let currencyCode: String
    private let locale: Locale
    private let dateFormatter: DateFormatter
    private var itemsByID: [String: StatementTransaction] = [:]

    private lazy var dataSource = UITableViewDiffableDataSource<Section, String>(tableView: tableView) { [weak self] table, indexPath, id in
        guard let self, let item = self.itemsByID[id],
              let cell = table.dequeueReusableCell(withIdentifier: StatementTransactionCell.reuseIdentifier, for: indexPath) as? StatementTransactionCell else {
            return nil
        }
        cell.configure(
            id: item.id,
            description: item.description,
            amount: item.amount.formatted(currencyCode: self.currencyCode, locale: self.locale),
            date: self.dateFormatter.string(from: item.occurredAt)
        )
        return cell
    }

    init(currencyCode: String, locale: Locale, timeZone: TimeZone) {
        self.currencyCode = currencyCode
        self.locale = locale
        dateFormatter = DateFormatter()
        dateFormatter.locale = locale
        dateFormatter.timeZone = timeZone
        dateFormatter.dateStyle = .medium
        dateFormatter.timeStyle = .short
        super.init(frame: .zero)
        setup()
        render(.idle)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("Use init(currencyCode:locale:timeZone:).")
    }

    func render(_ state: StatementViewState) {
        var items: [StatementTransaction] = []
        statusView.isHidden = false
        retryButton.isHidden = true
        initialSpinner.stopAnimating()
        paginationSpinner.stopAnimating()
        footer.isHidden = true

        switch state {
        case .idle:
            statusLabel.text = "O extrato ainda não foi carregado."
        case .loading:
            statusLabel.text = "Carregando extrato…"
            initialSpinner.startAnimating()
        case .empty:
            statusLabel.text = "Nenhuma transação para mostrar."
        case .failed:
            statusLabel.text = "Não foi possível carregar o extrato."
            retryButton.isHidden = false
        case .loaded(let page, let pagination):
            items = page.items
            statusView.isHidden = !items.isEmpty
            statusLabel.text = "Nenhuma transação nesta página."
            footer.isHidden = page.nextCursor == nil
            footerLabel.isHidden = pagination == .idle
            loadMoreButton.isHidden = pagination == .loading
            loadMoreButton.isEnabled = pagination != .loading
            if pagination == .loading {
                footerLabel.text = "Carregando mais transações…"
                paginationSpinner.startAnimating()
            } else if pagination == .failed {
                footerLabel.text = "Não foi possível carregar mais transações."
            }
            loadMoreButton.setTitle(pagination == .failed ? "Tentar novamente" : "Carregar mais", for: .normal)
        }
        if footer.isHidden {
            footer.arrangedSubviews.forEach { $0.isHidden = true }
            footer.directionalLayoutMargins = .zero
        } else {
            footer.directionalLayoutMargins = NSDirectionalEdgeInsets(top: 12, leading: 20, bottom: 12, trailing: 20)
        }
        apply(items)
    }

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        guard let id = dataSource.itemIdentifier(for: indexPath) else { return }
        onSelectTransaction?(id)
    }

    private func apply(_ items: [StatementTransaction]) {
        let oldIDs = Set(dataSource.snapshot().itemIdentifiers)
        var ids: [String] = []
        itemsByID = [:]
        for item in items {
            if itemsByID[item.id] == nil { ids.append(item.id) }
            itemsByID[item.id] = item
        }
        var snapshot = NSDiffableDataSourceSnapshot<Section, String>()
        snapshot.appendSections([.transactions])
        snapshot.appendItems(ids)
        snapshot.reconfigureItems(ids.filter { oldIDs.contains($0) })
        dataSource.apply(snapshot, animatingDifferences: false)
    }

    private func setup() {
        backgroundColor = .systemBackground
        tableView.backgroundColor = .systemBackground
        tableView.accessibilityIdentifier = "statement.list"
        tableView.delegate = self
        tableView.rowHeight = UITableView.automaticDimension
        tableView.estimatedRowHeight = 110
        tableView.register(StatementTransactionCell.self, forCellReuseIdentifier: StatementTransactionCell.reuseIdentifier)
        tableView.backgroundView = statusView
        tableView.tableFooterView = UIView()

        statusLabel.accessibilityIdentifier = "statement.status"
        initialSpinner.accessibilityIdentifier = "statement.initial-loading"
        footerLabel.accessibilityIdentifier = "statement.pagination-status"
        paginationSpinner.accessibilityIdentifier = "statement.pagination-loading"
        configureLabel(statusLabel)
        configureLabel(footerLabel)
        retryButton.addAction(UIAction { [weak self] _ in self?.onRetry?() }, for: .touchUpInside)
        loadMoreButton.addAction(UIAction { [weak self] _ in self?.onLoadMore?() }, for: .touchUpInside)

        let statusStack = UIStackView(arrangedSubviews: [initialSpinner, statusLabel, retryButton])
        statusStack.axis = .vertical
        statusStack.spacing = 16
        statusStack.translatesAutoresizingMaskIntoConstraints = false
        statusView.addSubview(statusStack)
        NSLayoutConstraint.activate([
            statusStack.centerYAnchor.constraint(equalTo: statusView.centerYAnchor),
            statusStack.leadingAnchor.constraint(equalTo: statusView.leadingAnchor, constant: 24),
            statusStack.trailingAnchor.constraint(equalTo: statusView.trailingAnchor, constant: -24)
        ])

        footer.axis = .vertical
        footer.spacing = 12
        footer.isLayoutMarginsRelativeArrangement = true
        footer.directionalLayoutMargins = NSDirectionalEdgeInsets(top: 12, leading: 20, bottom: 12, trailing: 20)
        [footerLabel, paginationSpinner, loadMoreButton].forEach { footer.addArrangedSubview($0) }
        let stack = UIStackView(arrangedSubviews: [tableView, footer])
        stack.axis = .vertical
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: safeAreaLayoutGuide.topAnchor),
            stack.leadingAnchor.constraint(equalTo: leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor),
            stack.bottomAnchor.constraint(equalTo: safeAreaLayoutGuide.bottomAnchor)
        ])
    }

    private func configureLabel(_ label: UILabel) {
        label.font = .preferredFont(forTextStyle: .body)
        label.adjustsFontForContentSizeCategory = true
        label.numberOfLines = 0
        label.textAlignment = .center
        label.textColor = .secondaryLabel
    }

}
