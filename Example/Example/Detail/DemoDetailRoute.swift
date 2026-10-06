import UIKit
import KirbyiOS
import WFRouter
import WildFunctionKit

/// Routes exposed by the detail module.
enum DemoDetailRoute: Route {
    case detail(id: String)
}

/// Registers the routes and deeplinks the detail module handles.
enum DemoDetailModule: RouteModule {
    private enum Deeplink {
        static let host = "detail"
        static let idParameter = "id"
        static let maxIDLength = 32
    }

    static func register(in navigator: Navigator) {
        navigator.register(DemoDetailRoute.self) { _ in
            DemoDetailViewController(viewModel: DemoDetailViewModel())
        }
        // wildfunction-demo://detail?id=1
        navigator.registerDeeplink(host: Deeplink.host) { url in
            detailID(from: url).map { DemoDetailRoute.detail(id: $0) }
        }
    }

    /// Deeplinks come from outside the app, so validate parameters before use.
    private static func detailID(from url: URL) -> String? {
        let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        guard let id = items.first(where: { $0.name == Deeplink.idParameter })?.value,
              !id.isEmpty,
              id.count <= Deeplink.maxIDLength,
              id.allSatisfy({ $0.isLetter || $0.isNumber })
        else { return nil }
        return id
    }
}
