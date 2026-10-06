import UIKit
import KirbyiOS
import WFRouter
import WildFunctionKit

/// List page: KirbyCollectionViewController with a diffable data source and compositional layout.
final class DemoListViewController: KirbyCollectionViewController {
    private enum Section: Hashable {
        case main
    }

    private struct InvalidResponse: Error {}

    let viewModel: DemoListViewModel

    private var dataSource: UICollectionViewDiffableDataSource<Section, DemoListItem>?

    init(viewModel: DemoListViewModel) {
        self.viewModel = viewModel
        super.init(collectionViewLayout: Self.makeLayout())
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

    override func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        collectionView.deselectItem(at: indexPath, animated: true)
        guard let item = dataSource?.itemIdentifier(for: indexPath) else { return }
        wf_open(DemoDetailRoute.detail(id: item.id))
    }
}
