import UIKit
import WildFunctionKit

/// Owns a page's plugins and forwards the host's lifecycle to them in insertion order.
///
/// Any `UIViewController` can adopt plugins by composing a host.
///
/// Forwarding works on a snapshot. Plugins added after `viewDidLoad` get it replayed, but not appear events.
/// In DEBUG, a plugin method taking longer than 16 ms logs a warning.
@MainActor
public final class KirbyPluginHost {
    /// A slow plugin call.
    struct SlowCall {
        let pluginType: String
        let method: String
        let duration: Duration
    }

    /// The page's context.
    public let context: KirbyContext

    private var plugins: [any KirbyPlugin] = []
    private var hasLoadedView = false

    /// Slow-call threshold. DEBUG only.
    var slowCallThreshold: Duration = .milliseconds(16)
    /// Slow-call handler. Logs a warning by default; replaceable in tests.
    var onSlowCall: @MainActor (SlowCall) -> Void = { call in
        AppLog.warning(
            "\(call.pluginType).\(call.method) took \(call.duration), exceeds one frame",
            category: .plugin
        )
    }

    /// Creates a host.
    public init(context: KirbyContext) {
        self.context = context
    }

    isolated deinit {
        detachAll()
    }

    /// Adds a plugin and calls `didAttach`. Duplicate instances are ignored.
    public func add(_ plugin: any KirbyPlugin) {
        guard !plugins.contains(where: { $0 === plugin }) else {
            AppLog.warning("\(type(of: plugin)) is already attached, ignored", category: .plugin)
            return
        }
        plugins = plugins + [plugin]

        measure(plugin, "didAttach") { $0.didAttach(to: context) }
        if hasLoadedView {
            measure(plugin, "viewDidLoad") { $0.viewDidLoad() }
        }
    }

    /// Creates and adds plugins from their classes, in order.
    public func add(classes: [any KirbyPlugin.Type]) {
        classes.forEach { add($0.init()) }
    }

    /// Adds plugins in order.
    public func add(_ plugins: [any KirbyPlugin]) {
        plugins.forEach { add($0) }
    }

    /// Removes a plugin after calling `willDetach`.
    public func remove(_ plugin: any KirbyPlugin) {
        guard plugins.contains(where: { $0 === plugin }) else { return }
        measure(plugin, "willDetach") { $0.willDetach(from: context) }
        plugins = plugins.filter { $0 !== plugin }
    }

    /// Finds a plugin by type.
    ///
    /// - Important: For tests and debugging only. Plugins must talk through events, not look each other up.
    public func plugin<P: KirbyPlugin>(ofType type: P.Type) -> P? {
        plugins.lazy.compactMap { $0 as? P }.first
    }

    /// Detaches every plugin in reverse insertion order. Safe to call more than once.
    public func detachAll() {
        let snapshot = plugins.reversed()
        plugins = []
        for plugin in snapshot {
            measure(plugin, "willDetach") { $0.willDetach(from: context) }
        }
    }

    // MARK: - View lifecycle forwarding

    /// Forwards `viewDidLoad` and remembers it for late plugins.
    public func viewDidLoad() {
        hasLoadedView = true
        forward("viewDidLoad") { $0.viewDidLoad() }
    }

    /// Forwards `viewWillAppear(_:)`.
    public func viewWillAppear(_ animated: Bool) {
        forward("viewWillAppear") { $0.viewWillAppear(animated) }
    }

    /// Forwards `viewIsAppearing(_:)`.
    public func viewIsAppearing(_ animated: Bool) {
        forward("viewIsAppearing") { $0.viewIsAppearing(animated) }
    }

    /// Forwards `viewDidAppear(_:)`.
    public func viewDidAppear(_ animated: Bool) {
        forward("viewDidAppear") { $0.viewDidAppear(animated) }
    }

    /// Forwards `viewWillDisappear(_:)`.
    public func viewWillDisappear(_ animated: Bool) {
        forward("viewWillDisappear") { $0.viewWillDisappear(animated) }
    }

    /// Forwards `viewDidDisappear(_:)`.
    public func viewDidDisappear(_ animated: Bool) {
        forward("viewDidDisappear") { $0.viewDidDisappear(animated) }
    }

    /// Forwards `viewWillLayoutSubviews()`.
    public func viewWillLayoutSubviews() {
        forward("viewWillLayoutSubviews") { $0.viewWillLayoutSubviews() }
    }

    /// Forwards `viewDidLayoutSubviews()`.
    public func viewDidLayoutSubviews() {
        forward("viewDidLayoutSubviews") { $0.viewDidLayoutSubviews() }
    }

    /// Forwards a trait change.
    public func traitsDidChange(_ previous: UITraitCollection) {
        forward("traitsDidChange") { $0.traitsDidChange(previous) }
    }

    // MARK: - Main request forwarding

    /// Forwards "main request will send".
    public func mainRequestWillSend(_ request: KirbyRequest, isRetry: Bool) {
        forward("mainRequestWillSend") { $0.mainRequestWillSend(request, isRetry: isRetry) }
    }

    /// Forwards "main request did receive".
    public func mainRequestDidReceive(_ response: KirbyResponse) {
        forward("mainRequestDidReceive") { $0.mainRequestDidReceive(response) }
    }

    /// Forwards "main request did parse".
    public func mainRequestDidParse(_ response: KirbyResponse) {
        forward("mainRequestDidParse") { $0.mainRequestDidParse(response) }
    }

    /// Forwards "main request did fail".
    public func mainRequestDidFail(_ error: KirbyRequestError) {
        forward("mainRequestDidFail") { $0.mainRequestDidFail(error) }
    }

    // MARK: - Private

    private func forward(_ method: String, _ body: (any KirbyPlugin) -> Void) {
        let snapshot = plugins
        for plugin in snapshot {
            measure(plugin, method, body)
        }
    }

    private func measure(_ plugin: any KirbyPlugin, _ method: String, _ body: (any KirbyPlugin) -> Void) {
        #if DEBUG
        let duration = ContinuousClock().measure { body(plugin) }
        if duration > slowCallThreshold {
            onSlowCall(SlowCall(pluginType: String(describing: type(of: plugin)), method: method, duration: duration))
        }
        #else
        body(plugin)
        #endif
    }
}
