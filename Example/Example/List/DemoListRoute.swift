import UIKit
import KirbyiOS
import WFRouter
import WildFunctionKit

enum DemoListRoute: Route {
    case list
}

enum DemoListModule: RouteModule {
    static func register(in navigator: Navigator) {
        navigator.register(DemoListRoute.self) { _ in
            DemoListViewController(viewModel: DemoListViewModel())
        }
    }
}
