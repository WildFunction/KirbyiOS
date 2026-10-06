import UIKit
import KirbyiOS
import WFRouter
import WildFunctionKit

@main
final class AppDelegate: UIResponder, UIApplicationDelegate {
    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        // List every module explicitly; each registers its own routes and deeplinks.
        Navigator.shared.install([DemoDetailModule.self, DemoListModule.self])
        Navigator.shared.allowedDeeplinkSchemes = [AppConstants.deeplinkScheme]
        // Swap the global performer. A real app plugs in its own networking here, or keeps the default.
        KirbyRequestConfiguration.defaultPerformer = DemoRequestPerformer()
        return true
    }
}

enum AppConstants {
    static let deeplinkScheme = "wildfunction-demo"
}
