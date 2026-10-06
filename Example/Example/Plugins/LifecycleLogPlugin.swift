import UIKit
import KirbyiOS
import WFRouter
import WildFunctionKit

/// Logs every lifecycle callback, including the main request's. Filter Console by category `plugin`.
///
/// Plugins have no initializer parameters; they read what they need from the context.
final class LifecycleLogPlugin: BaseKirbyPlugin {
    private var pageName = "?"

    private func log(_ method: String) {
        AppLog.debug("[\(pageName)] \(method)", category: .plugin)
    }

    override func didAttach(to context: KirbyContext) {
        super.didAttach(to: context)
        pageName = context.host.map { String(describing: type(of: $0)) } ?? "?"
        log("didAttach")
    }

    override func willDetach(from context: KirbyContext) {
        log("willDetach")
        super.willDetach(from: context)
    }

    override func viewDidLoad() { log("viewDidLoad") }
    override func viewWillAppear(_ animated: Bool) { log("viewWillAppear") }
    override func viewIsAppearing(_ animated: Bool) { log("viewIsAppearing") }
    override func viewDidAppear(_ animated: Bool) { log("viewDidAppear") }
    override func viewWillDisappear(_ animated: Bool) { log("viewWillDisappear") }
    override func viewDidDisappear(_ animated: Bool) { log("viewDidDisappear") }
    override func traitsDidChange(_ previous: UITraitCollection) { log("traitsDidChange") }

    override func mainRequestWillSend(_ request: KirbyRequest, isRetry: Bool) {
        log("mainRequestWillSend, isRetry = \(isRetry)")
    }

    override func mainRequestDidReceive(_ response: KirbyResponse) {
        log("mainRequestDidReceive, \(response.data.count) bytes in \(response.duration)")
    }

    override func mainRequestDidParse(_ response: KirbyResponse) { log("mainRequestDidParse") }
    override func mainRequestDidFail(_ error: KirbyRequestError) { log("mainRequestDidFail, \(error)") }
}
