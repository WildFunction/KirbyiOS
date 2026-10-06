import UIKit
import KirbyiOS
import WFRouter
import WildFunctionKit

/// Home page: push, present and deeplink with typed routes.
final class HomeViewController: KirbyViewController {
    private struct Entry {
        let title: String
        let action: @MainActor (HomeViewController) -> Void
    }

    private static let demoItemID = "1"

    private let entries: [Entry] = [
        Entry(title: "Push Detail") { $0.wf_open(DemoDetailRoute.detail(id: demoItemID)) },
        Entry(title: "Present Detail") { $0.wf_open(DemoDetailRoute.detail(id: "2"), style: .present()) },
        Entry(title: "List") { $0.wf_open(DemoListRoute.list) },
        Entry(title: "Open Deeplink") { _ in
            guard let url = URL(string: "\(AppConstants.deeplinkScheme)://detail?id=\(demoItemID)") else { return }
            Navigator.shared.open(url: url)
        },
    ]

    override func pluginClasses() -> [any KirbyPlugin.Type] {
        [LifecycleLogPlugin.self]
    }

    override func setupUI() {
        title = "WildFunctionKit"
        view.backgroundColor = .systemBackground

        let buttons = entries.enumerated().map { index, entry in
            var configuration = UIButton.Configuration.filled()
            configuration.title = entry.title
            configuration.buttonSize = .large
            return UIButton(configuration: configuration, primaryAction: UIAction { [weak self] _ in
                guard let self else { return }
                self.entries[index].action(self)
            })
        }

        let stack = UIStackView(arrangedSubviews: buttons)
        stack.axis = .vertical
        stack.spacing = 16
        stack.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.centerYAnchor.constraint(equalTo: view.safeAreaLayoutGuide.centerYAnchor),
            stack.leadingAnchor.constraint(equalTo: view.layoutMarginsGuide.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: view.layoutMarginsGuide.trailingAnchor),
        ])
    }
}
