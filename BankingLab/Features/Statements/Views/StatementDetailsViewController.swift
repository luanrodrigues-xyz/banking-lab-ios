import UIKit

@MainActor
final class StatementDetailsViewController: UIViewController {
    private let transaction: StatementTransaction
    private let currencyCode: String
    private let locale: Locale
    private let timeZone: TimeZone

    init(transaction: StatementTransaction, currencyCode: String, locale: Locale, timeZone: TimeZone) {
        self.transaction = transaction
        self.currencyCode = currencyCode
        self.locale = locale
        self.timeZone = timeZone
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("Use init(transaction:currencyCode:locale:timeZone:).")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "Detalhes"
        view.backgroundColor = .systemBackground
        view.accessibilityIdentifier = "statement.details"
        let formatter = DateFormatter()
        formatter.locale = locale
        formatter.timeZone = timeZone
        formatter.dateStyle = .long
        formatter.timeStyle = .short
        let description = label(transaction.description.isEmpty ? "Transação sem descrição" : transaction.description, style: .title2, id: "description")
        description.accessibilityTraits.insert(.header)
        let amount = label(transaction.amount.formatted(currencyCode: currencyCode, locale: locale), style: .largeTitle, id: "amount")
        amount.accessibilityLabel = "Valor da transação"
        amount.accessibilityValue = amount.text
        let date = label(formatter.string(from: transaction.occurredAt), style: .body, id: "date")
        date.accessibilityLabel = "Data da transação"
        date.accessibilityValue = date.text
        let identifier = label("Identificador: \(transaction.id)", style: .footnote, id: "id")
        let stack = UIStackView(arrangedSubviews: [description, amount, date, identifier])
        stack.axis = .vertical
        stack.spacing = 24
        stack.translatesAutoresizingMaskIntoConstraints = false
        let scroll = UIScrollView()
        scroll.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(scroll)
        scroll.addSubview(stack)
        NSLayoutConstraint.activate([
            scroll.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            scroll.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scroll.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scroll.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor),
            stack.topAnchor.constraint(equalTo: scroll.contentLayoutGuide.topAnchor, constant: 24),
            stack.leadingAnchor.constraint(equalTo: scroll.contentLayoutGuide.leadingAnchor, constant: 20),
            stack.trailingAnchor.constraint(equalTo: scroll.contentLayoutGuide.trailingAnchor, constant: -20),
            stack.bottomAnchor.constraint(equalTo: scroll.contentLayoutGuide.bottomAnchor, constant: -24),
            stack.widthAnchor.constraint(equalTo: scroll.frameLayoutGuide.widthAnchor, constant: -40)
        ])
    }

    private func label(_ text: String, style: UIFont.TextStyle, id: String) -> UILabel {
        let label = UILabel()
        label.text = text
        label.font = .preferredFont(forTextStyle: style)
        label.adjustsFontForContentSizeCategory = true
        label.numberOfLines = 0
        label.accessibilityIdentifier = "statement.details.\(id)"
        return label
    }
}
