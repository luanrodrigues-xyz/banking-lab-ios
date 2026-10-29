import UIKit

@MainActor
final class PrimaryButton: UIButton {
    init(title: String, accessibilityIdentifier: String) {
        super.init(frame: .zero)
        var configuration = UIButton.Configuration.filled()
        configuration.buttonSize = .large
        configuration.titleLineBreakMode = .byWordWrapping
        configuration.titleAlignment = .center
        configuration.contentInsets = NSDirectionalEdgeInsets(top: 12, leading: 16, bottom: 12, trailing: 16)
        self.configuration = configuration
        setTitle(title, for: .normal)
        self.accessibilityIdentifier = accessibilityIdentifier
        configurationUpdateHandler = { button in
            guard var configuration = button.configuration else { return }
            let font = UIFont.preferredFont(forTextStyle: .headline, compatibleWith: button.traitCollection)
            configuration.titleTextAttributesTransformer = UIConfigurationTextAttributesTransformer { attributes in
                var attributes = attributes
                attributes.font = font
                return attributes
            }
            button.configuration = configuration
        }
        let minimumHeight = heightAnchor.constraint(greaterThanOrEqualToConstant: 44)
        minimumHeight.priority = .defaultHigh
        minimumHeight.isActive = true
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("Use init(title:accessibilityIdentifier:).")
    }
}
