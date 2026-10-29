import UIKit

@MainActor
final class StatementTransactionCell: UITableViewCell {
    static let reuseIdentifier = "StatementTransactionCell"

    private let descriptionLabel = UILabel()
    private let amountLabel = UILabel()
    private let dateLabel = UILabel()

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        descriptionLabel.font = .preferredFont(forTextStyle: .body)
        amountLabel.font = .preferredFont(forTextStyle: .headline)
        dateLabel.font = .preferredFont(forTextStyle: .subheadline)
        dateLabel.textColor = .secondaryLabel

        let stack = UIStackView(arrangedSubviews: [descriptionLabel, amountLabel, dateLabel])
        stack.axis = .vertical
        stack.spacing = 4
        stack.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(stack)
        contentView.directionalLayoutMargins = NSDirectionalEdgeInsets(top: 14, leading: 20, bottom: 14, trailing: 12)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: contentView.layoutMarginsGuide.topAnchor),
            stack.leadingAnchor.constraint(equalTo: contentView.layoutMarginsGuide.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: contentView.layoutMarginsGuide.trailingAnchor),
            stack.bottomAnchor.constraint(equalTo: contentView.layoutMarginsGuide.bottomAnchor)
        ])
        for label in [descriptionLabel, amountLabel, dateLabel] {
            label.numberOfLines = 0
            label.adjustsFontForContentSizeCategory = true
        }
        accessoryType = .disclosureIndicator
        isAccessibilityElement = true
        accessibilityTraits = .button
        accessibilityHint = "Mostra os detalhes da transação."
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("Use init(style:reuseIdentifier:).")
    }

    func configure(id: String, description: String, amount: String, date: String) {
        let title = description.isEmpty ? "Transação sem descrição" : description
        descriptionLabel.text = title
        amountLabel.text = amount
        dateLabel.text = date
        accessibilityIdentifier = "statement.transaction.\(id)"
        accessibilityLabel = title
        accessibilityValue = "\(amount), \(date)"
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        descriptionLabel.text = nil
        amountLabel.text = nil
        dateLabel.text = nil
        accessibilityIdentifier = nil
        accessibilityLabel = nil
        accessibilityValue = nil
    }
}
