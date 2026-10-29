import UIKit

@MainActor
final class AccountViewController: UIViewController {
    var onShowStatement: (@MainActor () -> Void)?
    private let balance: MonetaryAmount
    private let currencyCode: String
    private let locale: Locale

    init(balance: MonetaryAmount, currencyCode: String, locale: Locale) {
        self.balance = balance
        self.currencyCode = currencyCode
        self.locale = locale
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("Use init(balance:currencyCode:locale:).")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "Conta"
        view.backgroundColor = .systemBackground
        let heading = label("Conta de demonstração", style: .title2)
        heading.accessibilityTraits.insert(.header)
        let balanceTitle = label("Saldo fictício", style: .body)
        balanceTitle.textColor = .secondaryLabel
        balanceTitle.isAccessibilityElement = false
        let amount = label(balance.formatted(currencyCode: currencyCode, locale: locale), style: .largeTitle)
        amount.accessibilityIdentifier = "account.balance"
        amount.accessibilityLabel = "Saldo fictício"
        amount.accessibilityValue = amount.text
        let notice = label("Dados fictícios para estudo. Nenhuma operação bancária é realizada.", style: .footnote)
        notice.textColor = .secondaryLabel
        let button = PrimaryButton(title: "Ver extrato", accessibilityIdentifier: "account.statement")
        button.addAction(UIAction { [weak self] _ in self?.onShowStatement?() }, for: .touchUpInside)

        let stack = UIStackView(arrangedSubviews: [heading, balanceTitle, amount, button, notice])
        stack.axis = .vertical
        stack.spacing = 20
        stack.setCustomSpacing(8, after: balanceTitle)
        stack.setCustomSpacing(32, after: amount)
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

    private func label(_ text: String, style: UIFont.TextStyle) -> UILabel {
        let label = UILabel()
        label.text = text
        label.font = .preferredFont(forTextStyle: style)
        label.adjustsFontForContentSizeCategory = true
        label.numberOfLines = 0
        return label
    }
}
