import KirbyiOS
import UIKit
import WildFunctionKit

final class ___VARIABLE_productName:identifier___ViewController: KirbyViewController {
    let viewModel: ___VARIABLE_productName:identifier___ViewModel

    init(viewModel: ___VARIABLE_productName:identifier___ViewModel) {
        self.viewModel = viewModel
        super.init()
    }

    /// Plugin classes for this page. The base class creates and attaches them.
    override func pluginClasses() -> [any KirbyPlugin.Type] {
        []
    }

    /// The main request: URL and parameters. Return nil when the page has none.
    override func mainRequest() -> KirbyRequest? {
        nil
    }

    /// Parse the response and update the view model. Throw to report a parsing failure.
    override func handleMainResponse(_ response: KirbyResponse) throws {
    }

    /// The main request failed.
    override func mainRequestDidFail(_ error: KirbyRequestError) {
    }

    /// Build the view hierarchy.
    override func setupUI() {
        view.backgroundColor = .systemBackground
    }

    /// Subscribe to context events. Capture self weakly in handlers.
    override func setupEvents() {
    }

    /// Apply view model state to views. Called again when a property read here changes.
    override func render() {
        title = viewModel.title
    }
}
