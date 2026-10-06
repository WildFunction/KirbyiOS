import Foundation
import KirbyiOS
import WFRouter
import WildFunctionKit

struct DemoListItem: Hashable, Sendable, SmartCodableX {
    var id = ""
    var title = ""
}

/// Response of the list API.
struct DemoListResponse: SmartCodableX {
    var items: [DemoListItem] = []
}

@MainActor @Observable
final class DemoListViewModel: KirbyViewModel {
    private(set) var items: [DemoListItem] = []

    func apply(_ response: DemoListResponse) {
        items = response.items
    }
}
