import KirbyiOS
import UIKit
import WildFunctionKit

final class ___VARIABLE_productName:identifier___ViewController: KirbyViewController {
    private enum Section: Hashable {
        case main
    }

    let viewModel: ___VARIABLE_productName:identifier___ViewModel

    private let collectionView = UICollectionView(frame: .zero, collectionViewLayout: ___VARIABLE_productName:identifier___ViewController.makeLayout())
    private var dataSource: UICollectionViewDiffableDataSource<Section, ___VARIABLE_productName:identifier___Item>?

    init(viewModel: ___VARIABLE_productName:identifier___ViewModel) {
        self.viewModel = viewModel
        super.init()
    }

    private static func makeLayout() -> UICollectionViewLayout {
        UICollectionViewCompositionalLayout.list(using: UICollectionLayoutListConfiguration(appearance: .plain))
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

    /// Add the collection view, register cells and configure the data source.
    override func setupUI() {
        collectionView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(collectionView)
        // Pin to the view, not the safe area, so large titles collapse while scrolling.
        NSLayoutConstraint.activate([
            collectionView.topAnchor.constraint(equalTo: view.topAnchor),
            collectionView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            collectionView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            collectionView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
        ])

        let registration = UICollectionView.CellRegistration<UICollectionViewListCell, ___VARIABLE_productName:identifier___Item> { cell, _, item in
            var content = cell.defaultContentConfiguration()
            content.text = item.title
            cell.contentConfiguration = content
        }
        dataSource = UICollectionViewDiffableDataSource(collectionView: collectionView) { collectionView, indexPath, item in
            collectionView.dequeueConfiguredReusableCell(using: registration, for: indexPath, item: item)
        }
    }

    /// Subscribe to context events. Capture self weakly in handlers.
    override func setupEvents() {
    }

    /// Build a snapshot from the view model. Called again when viewModel.items changes.
    override func render() {
        var snapshot = NSDiffableDataSourceSnapshot<Section, ___VARIABLE_productName:identifier___Item>()
        snapshot.appendSections([.main])
        snapshot.appendItems(viewModel.items)
        dataSource?.apply(snapshot)
    }
}
