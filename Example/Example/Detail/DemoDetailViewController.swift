import UIKit
import KirbyiOS
import WFRouter
import WildFunctionKit

/// Detail page: context keys, plugins, the main request, events and view model driven rendering.
final class DemoDetailViewController: KirbyViewController {
    private enum Layout {
        static let spacing: CGFloat = 12
    }

    private struct InvalidResponse: Error {}

    let viewModel: DemoDetailViewModel

    private let titleLabel = UILabel()
    private let subtitleLabel = UILabel()
    private let contextLabel = UILabel()

    init(viewModel: DemoDetailViewModel) {
        self.viewModel = viewModel
        super.init()
    }

    // MARK: Plugins: list the classes, the base class creates and attaches them

    override func pluginClasses() -> [any KirbyPlugin.Type] {
        [LifecycleLogPlugin.self, LoadingStatePlugin.self, LoadedCountPlugin.self]
    }

    // MARK: Main request: supply URL and parameters, the base class and plugins do the rest

    override func mainRequest() -> KirbyRequest? {
        KirbyRequest(url: DemoAPI.host + DemoAPI.detailPath, parameters: ["id": context[DemoItemIDKey.self]])
    }

    override func handleMainResponse(_ response: KirbyResponse) throws {
        guard let detail = SafeJSON.decode(DemoDetail.self, from: response.data) else { throw InvalidResponse() }
        viewModel.apply(detail)
        context.event.dispatch(DemoDetailEvent.loaded, detail.title)
    }

    override func mainRequestDidFail(_ error: KirbyRequestError) {
        viewModel.applyFailure()
    }

    // MARK: View

    override func setupUI() {
        view.backgroundColor = .systemBackground
        navigationItem.rightBarButtonItem = UIBarButtonItem(
            title: "Retry",
            primaryAction: UIAction { [weak self] _ in self?.retryMainRequest() }
        )

        titleLabel.font = .preferredFont(forTextStyle: .title1)
        subtitleLabel.font = .preferredFont(forTextStyle: .body)
        subtitleLabel.textColor = .secondaryLabel
        contextLabel.font = .preferredFont(forTextStyle: .footnote)
        contextLabel.textColor = .tertiaryLabel
        contextLabel.numberOfLines = 0
        // Route parameters were written to the context in configure.
        contextLabel.text = "context: id = \(context[DemoItemIDKey.self]), source = \(context[DemoEntrySourceKey.self])"

        let stack = UIStackView(arrangedSubviews: [titleLabel, subtitleLabel, contextLabel])
        stack.axis = .vertical
        stack.spacing = Layout.spacing
        stack.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: Layout.spacing),
            stack.leadingAnchor.constraint(equalTo: view.layoutMarginsGuide.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: view.layoutMarginsGuide.trailingAnchor),
        ])
    }

    /// Applies state to views. Called again when a view model property read here changes.
    override func render() {
        title = viewModel.title
        titleLabel.text = viewModel.title
        subtitleLabel.text = viewModel.subtitle
    }
}

extension DemoDetailViewController: RouteConfigurable {
    /// Early configuration before showing: the view is not loaded and plugins are not attached yet.
    func configure(with route: DemoDetailRoute, info: RouteInfo) {
        switch route {
        case let .detail(id):
            context[DemoItemIDKey.self] = id
        }
        context[DemoEntrySourceKey.self] = info.url == nil
            ? String(describing: type(of: info.source))
            : "deeplink"
    }
}
