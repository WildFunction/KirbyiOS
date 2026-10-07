import UIKit
import KirbyiOS
import WFRouter
import WildFunctionKit

/// List page: a collection view with a diffable data source and compositional layout.
final class DemoListViewController: KirbyViewController, UICollectionViewDelegate {
    private enum Section: Hashable {
        case main
    }

    private struct InvalidResponse: Error {}

    let viewModel: DemoListViewModel

    private let collectionView = UICollectionView(frame: .zero, collectionViewLayout: DemoListViewController.makeLayout())
    private var dataSource: UICollectionViewDiffableDataSource<Section, DemoListItem>?

    init(viewModel: DemoListViewModel) {
        self.viewModel = viewModel
        super.init()
    }

    private static func makeLayout() -> UICollectionViewLayout {
        UICollectionViewCompositionalLayout.list(using: UICollectionLayoutListConfiguration(appearance: .insetGrouped))
    }

    override func pluginClasses() -> [any KirbyPlugin.Type] {
        [LifecycleLogPlugin.self, LoadingStatePlugin.self]
    }

    override func mainRequest() -> KirbyRequest? {
        KirbyRequest(url: DemoAPI.host + DemoAPI.listPath)
    }

    override func handleMainResponse(_ response: KirbyResponse) throws {
        guard let list = SafeJSON.decode(DemoListResponse.self, from: response.data) else { throw InvalidResponse() }
        viewModel.apply(list)
    }

    override func setupUI() {
        title = "List"

        collectionView.delegate = self
        collectionView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(collectionView)
        // Pin to the view, not the safe area, so large titles collapse while scrolling.
        NSLayoutConstraint.activate([
            collectionView.topAnchor.constraint(equalTo: view.topAnchor),
            collectionView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            collectionView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            collectionView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
        ])

        let registration = UICollectionView.CellRegistration<UICollectionViewListCell, DemoListItem> { cell, _, item in
            var content = cell.defaultContentConfiguration()
            content.text = item.title
            cell.contentConfiguration = content
            cell.accessories = [.disclosureIndicator()]
        }
        dataSource = UICollectionViewDiffableDataSource(collectionView: collectionView) { collectionView, indexPath, item in
            collectionView.dequeueConfiguredReusableCell(using: registration, for: indexPath, item: item)
        }
    }

    /// Builds a snapshot from the view model. Called again only when `viewModel.items` changes.
    override func render() {
        var snapshot = NSDiffableDataSourceSnapshot<Section, DemoListItem>()
        snapshot.appendSections([.main])
        snapshot.appendItems(viewModel.items)
        dataSource?.apply(snapshot)
    }

    func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        collectionView.deselectItem(at: indexPath, animated: true)
        guard let item = dataSource?.itemIdentifier(for: indexPath) else { return }
        wf_open(DemoDetailRoute.detail(id: item.id))
    }
}
