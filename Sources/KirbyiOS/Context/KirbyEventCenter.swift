import Foundation
import WildFunctionKit

/// Page-scoped event center, one per context, used by the page, its child pages and plugins.
///
/// Events are identified by name and may carry a payload of any type.
///
/// ```swift
/// context.event.subscribe("itemSaved", as: String.self) { [weak self] itemID in
///     self?.refresh(itemID)
/// }
/// context.event.dispatch("itemSaved", "42")
/// ```
///
/// Dispatch is synchronous and runs handlers in subscription order, on a snapshot of the list.
/// Handlers subscribed after a dispatch do not receive it.
///
/// - Important: Handlers are retained by the center, which the page retains.
///   Capture the page or plugin with `[weak self]` to avoid a retain cycle.
@MainActor
public final class KirbyEventCenter {
    /// Maximum recursive dispatch depth for the same event name.
    public static let maxRecursionDepth = 16

    private struct Subscriber {
        let id: UInt64
        let handler: @MainActor (Any?) -> Void
    }

    private var subscribers: [String: [Subscriber]] = [:]
    private var dispatchDepth: [String: Int] = [:]
    private var nextID: UInt64 = 0

    /// Creates an empty event center. Normally you use ``KirbyContext/event`` instead.
    public init() {}

    /// Subscribes to an event.
    ///
    /// - Parameters:
    ///   - name: The event name.
    ///   - handler: Called synchronously on the main actor with the payload, which may be `nil`.
    /// - Returns: A token for cancelling. May be discarded.
    @discardableResult
    public func subscribe(
        _ name: String,
        handler: @escaping @MainActor (Any?) -> Void
    ) -> KirbyEventSubscription {
        let id = nextID
        nextID += 1
        subscribers[name, default: []].append(Subscriber(id: id, handler: handler))

        return KirbyEventSubscription { [weak self] in
            self?.removeSubscriber(id: id, name: name)
        }
    }

    /// Subscribes with a typed payload. The handler is skipped when the payload is missing or of another type.
    @discardableResult
    public func subscribe<Payload>(
        _ name: String,
        as type: Payload.Type,
        handler: @escaping @MainActor (Payload) -> Void
    ) -> KirbyEventSubscription {
        subscribe(name) { payload in
            guard let typed = payload as? Payload else {
                AppLog.warning(
                    "Event \(name) expected payload of type \(Payload.self), got \(String(describing: payload))",
                    category: .event
                )
                return
            }
            handler(typed)
        }
    }

    /// Dispatches an event synchronously.
    ///
    /// - Parameters:
    ///   - name: The event name.
    ///   - payload: Data delivered to handlers.
    public func dispatch(_ name: String, _ payload: Any? = nil) {
        let depth = dispatchDepth[name, default: 0]
        guard depth < Self.maxRecursionDepth else {
            AppLog.error(
                "Event \(name) dispatched recursively more than \(Self.maxRecursionDepth) levels deep, aborted",
                category: .event
            )
            return
        }

        let snapshot = subscribers[name] ?? []
        guard !snapshot.isEmpty else {
            AppLog.debug("Event \(name) dispatched with no subscribers", category: .event)
            return
        }

        dispatchDepth[name] = depth + 1
        defer { dispatchDepth[name] = depth == 0 ? nil : depth }

        for subscriber in snapshot {
            subscriber.handler(payload)
        }
    }

    /// Removes every subscription. Called when the page is torn down to break potential cycles.
    public func removeAll() {
        subscribers = [:]
    }

    private func removeSubscriber(id: UInt64, name: String) {
        guard let list = subscribers[name] else { return }
        let remaining = list.filter { $0.id != id }
        subscribers[name] = remaining.isEmpty ? nil : remaining
    }
}
