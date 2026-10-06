import KirbyiOS
import WFRouter
import WildFunctionKit

/// The item shown by the detail page. Written by the router in `configure(with:info:)`.
enum DemoItemIDKey: KirbyContextKey {
    static let defaultValue = ""
}

/// Where the detail page was opened from, for tracking plugins.
enum DemoEntrySourceKey: KirbyContextKey {
    static let defaultValue = "unknown"
}
