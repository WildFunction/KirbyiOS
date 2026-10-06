import UIKit
import KirbyiOS
import WFRouter
import WildFunctionKit

/// Shows page-to-plugin events: counts the detail page's "loaded" events in a banner.
final class LoadedCountPlugin: BaseKirbyPlugin {
    private enum Layout {
        static let bottomInset: CGFloat = 24
    }

    private let banner = UILabel()
    private var loadCount = 0

    override func didAttach(to context: KirbyContext) {
        super.didAttach(to: context)
        observe(DemoDetailEvent.loaded, as: String.self) { [weak self] title in
            guard let self else { return }
            self.loadCount += 1
            self.banner.text = "plugin received event: \(title) loaded \(self.loadCount)x"
        }
    }

    override func viewDidLoad() {
        guard let hostView = context?.host?.view else { return }
        banner.font = .preferredFont(forTextStyle: .footnote)
        banner.textColor = .secondaryLabel
        banner.textAlignment = .center
        banner.numberOfLines = 0
        banner.translatesAutoresizingMaskIntoConstraints = false
        hostView.addSubview(banner)
        NSLayoutConstraint.activate([
            banner.leadingAnchor.constraint(equalTo: hostView.layoutMarginsGuide.leadingAnchor),
            banner.trailingAnchor.constraint(equalTo: hostView.layoutMarginsGuide.trailingAnchor),
            banner.bottomAnchor.constraint(
                equalTo: hostView.safeAreaLayoutGuide.bottomAnchor,
                constant: -Layout.bottomInset
            ),
        ])
    }

    override func willDetach(from context: KirbyContext) {
        banner.removeFromSuperview()
        super.willDetach(from: context)
    }
}
