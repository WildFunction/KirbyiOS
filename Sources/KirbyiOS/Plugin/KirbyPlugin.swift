import UIKit
import WildFunctionKit

/// A page plugin for cross-cutting concerns: tracking, timing, loading / empty / error states and the like.
///
/// Pages list plugin classes in `pluginClasses()`; the base class creates and attaches them.
/// Every lifecycle callback, including the main request's, is forwarded in list order.
/// All methods have empty default implementations.
///
/// Plugins hold no business logic, no view model and no references to each other;
/// they talk to the page and to other plugins through `context.event`, and read configuration from `context`.
@MainActor
public protocol KirbyPlugin: AnyObject {
    /// The base class creates plugins through this initializer.
    init()

    /// Called when the plugin is added to a page. Keep the context (weakly) and subscribe to events here.
    func didAttach(to context: KirbyContext)
    /// Called before the plugin is removed, either manually or because the page is going away.
    func willDetach(from context: KirbyContext)

    // MARK: View lifecycle

    /// Mirrors `viewDidLoad()`. Replayed once for plugins attached after the view loaded.
    func viewDidLoad()
    /// Mirrors `viewWillAppear(_:)`.
    func viewWillAppear(_ animated: Bool)
    /// Mirrors `viewIsAppearing(_:)`.
    func viewIsAppearing(_ animated: Bool)
    /// Mirrors `viewDidAppear(_:)`.
    func viewDidAppear(_ animated: Bool)
    /// Mirrors `viewWillDisappear(_:)`.
    func viewWillDisappear(_ animated: Bool)
    /// Mirrors `viewDidDisappear(_:)`.
    func viewDidDisappear(_ animated: Bool)
    /// Mirrors `viewWillLayoutSubviews()`.
    func viewWillLayoutSubviews()
    /// Mirrors `viewDidLayoutSubviews()`.
    func viewDidLayoutSubviews()
    /// One of the host's observed traits changed (appearance, size class, content size).
    func traitsDidChange(_ previous: UITraitCollection)

    // MARK: Main request lifecycle

    /// The main request is about to be sent. `isRetry` is `true` for retries.
    func mainRequestWillSend(_ request: KirbyRequest, isRetry: Bool)
    /// A response arrived; the page has not parsed it yet.
    func mainRequestDidReceive(_ response: KirbyResponse)
    /// The page parsed the response successfully.
    func mainRequestDidParse(_ response: KirbyResponse)
    /// The main request failed. Not called for cancelled requests.
    func mainRequestDidFail(_ error: KirbyRequestError)
}

extension KirbyPlugin {
    public func didAttach(to context: KirbyContext) {}
    public func willDetach(from context: KirbyContext) {}

    public func viewDidLoad() {}
    public func viewWillAppear(_ animated: Bool) {}
    public func viewIsAppearing(_ animated: Bool) {}
    public func viewDidAppear(_ animated: Bool) {}
    public func viewWillDisappear(_ animated: Bool) {}
    public func viewDidDisappear(_ animated: Bool) {}
    public func viewWillLayoutSubviews() {}
    public func viewDidLayoutSubviews() {}
    public func traitsDidChange(_ previous: UITraitCollection) {}

    public func mainRequestWillSend(_ request: KirbyRequest, isRetry: Bool) {}
    public func mainRequestDidReceive(_ response: KirbyResponse) {}
    public func mainRequestDidParse(_ response: KirbyResponse) {}
    public func mainRequestDidFail(_ error: KirbyRequestError) {}
}

/// Optional plugin base class: keeps the context and cancels `observe` subscriptions on detach.
///
/// ```swift
/// final class SavedItemsPlugin: BaseKirbyPlugin {
///     override func didAttach(to context: KirbyContext) {
///         super.didAttach(to: context)
///         observe("itemSaved", as: String.self) { [weak self] itemID in
///             self?.track(itemID)
///         }
///     }
/// }
/// ```
@MainActor
open class BaseKirbyPlugin: KirbyPlugin {
    /// The context of the page this plugin is attached to, or `nil`.
    public private(set) weak var context: KirbyContext?

    private var subscriptions: [KirbyEventSubscription] = []

    /// Creates the plugin. Subclasses must not add initializers with parameters.
    public required init() {}

    /// Keeps the context. Overrides must call `super`.
    open func didAttach(to context: KirbyContext) {
        self.context = context
    }

    /// Cancels `observe` subscriptions and clears the context. Overrides must call `super`.
    open func willDetach(from context: KirbyContext) {
        subscriptions.forEach { $0.cancel() }
        subscriptions = []
        self.context = nil
    }

    /// Subscribes to a page event until the plugin detaches. Call after attaching.
    public func observe(_ name: String, handler: @escaping @MainActor (Any?) -> Void) {
        guard let subscription = context?.event.subscribe(name, handler: handler) else { return }
        subscriptions = subscriptions + [subscription]
    }

    /// Subscribes with a typed payload until the plugin detaches. Call after attaching.
    public func observe<Payload>(
        _ name: String,
        as type: Payload.Type,
        handler: @escaping @MainActor (Payload) -> Void
    ) {
        guard let subscription = context?.event.subscribe(name, as: type, handler: handler) else { return }
        subscriptions = subscriptions + [subscription]
    }

    open func viewDidLoad() {}
    open func viewWillAppear(_ animated: Bool) {}
    open func viewIsAppearing(_ animated: Bool) {}
    open func viewDidAppear(_ animated: Bool) {}
    open func viewWillDisappear(_ animated: Bool) {}
    open func viewDidDisappear(_ animated: Bool) {}
    open func viewWillLayoutSubviews() {}
    open func viewDidLayoutSubviews() {}
    open func traitsDidChange(_ previous: UITraitCollection) {}

    open func mainRequestWillSend(_ request: KirbyRequest, isRetry: Bool) {}
    open func mainRequestDidReceive(_ response: KirbyResponse) {}
    open func mainRequestDidParse(_ response: KirbyResponse) {}
    open func mainRequestDidFail(_ error: KirbyRequestError) {}
}
