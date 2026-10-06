import Foundation
import KirbyiOS
import WFRouter
import WildFunctionKit

/// Detail model returned by the API, decoded leniently with SmartCodable.
struct DemoDetail: SmartCodableX {
    var id = ""
    var title = ""
    var price = 0.0
}

/// Detail page state. The base class sends the request; the view model only turns results into state.
@MainActor @Observable
final class DemoDetailViewModel: KirbyViewModel {
    private(set) var title = "Loading…"
    private(set) var subtitle = ""

    func apply(_ detail: DemoDetail) {
        title = detail.title
        subtitle = "id = \(detail.id), price = \(detail.price)"
    }

    func applyFailure() {
        title = "Failed to load"
        subtitle = "Tap Retry to try again"
    }
}
