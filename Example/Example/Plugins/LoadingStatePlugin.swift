import UIKit
import KirbyiOS
import WFRouter
import WildFunctionKit

/// Shows a loading indicator while the host's main request is in flight.
///
/// It knows nothing about the page or its view model.
final class LoadingStatePlugin: BaseKirbyPlugin {
    private let indicator = UIActivityIndicatorView(style: .large)

    override func viewDidLoad() {
        guard let hostView = context?.host?.view else { return }
        indicator.hidesWhenStopped = true
        indicator.translatesAutoresizingMaskIntoConstraints = false
        hostView.addSubview(indicator)
        NSLayoutConstraint.activate([
            indicator.centerXAnchor.constraint(equalTo: hostView.centerXAnchor),
            indicator.centerYAnchor.constraint(equalTo: hostView.centerYAnchor),
        ])
    }

    override func willDetach(from context: KirbyContext) {
        indicator.removeFromSuperview()
        super.willDetach(from: context)
    }

    override func mainRequestWillSend(_ request: KirbyRequest, isRetry: Bool) {
        indicator.superview?.bringSubviewToFront(indicator)
        indicator.startAnimating()
    }

    override func mainRequestDidParse(_ response: KirbyResponse) {
        indicator.stopAnimating()
    }

    override func mainRequestDidFail(_ error: KirbyRequestError) {
        indicator.stopAnimating()
    }
}
