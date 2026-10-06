import KirbyiOS
import WFRouter
import WildFunctionKit

/// Event names of the detail page, defined once so both sides share the same constant.
enum DemoDetailEvent {
    /// The detail finished loading. Payload: the title (`String`).
    static let loaded = "demoDetailLoaded"
}
