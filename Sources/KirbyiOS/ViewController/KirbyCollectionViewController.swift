import UIKit
import WildFunctionKit

/// List page base class. Behaves exactly like ``KirbyViewController``, on top of `UICollectionViewController`.
@MainActor
open class KirbyCollectionViewController: UICollectionViewController, KirbyHosting {
    /// The page's context.
    public let context: KirbyContext
    /// The page's plugin host.
    public let pluginHost: KirbyPluginHost

    /// Whether this page created the context. A child sharing its parent's context must not clear its events.
    private let ownsContext: Bool
    private var hasInstalledPlugins = false
    private var hasInstalledDeferredPlugins = false
    private let renderTracker = KirbyRenderTracker()
    private let mainRequestRunner = KirbyMainRequestRunner()

    /// Creates a list page with a layout.
    ///
    /// - Parameters:
    ///   - layout: The collection view layout.
    ///   - context: Pass a parent page's context to share it with this page.
    public init(collectionViewLayout layout: UICollectionViewLayout, context: KirbyContext? = nil) {
        let resolved = context ?? KirbyContext()
        self.context = resolved
        ownsContext = context == nil
        pluginHost = KirbyPluginHost(context: resolved)
        super.init(collectionViewLayout: layout)
        if resolved.host == nil {
            resolved.host = self
        }
    }

    @available(*, unavailable)
    public required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported, KirbyCollectionViewController is code-only")
    }

    // iOS 18.4+ lets us clean up on the main actor with an isolated deinit.
    isolated deinit {
        mainRequestRunner.cancel()
        KirbySupport.tearDown(context: context, pluginHost: pluginHost, clearsEvents: ownsContext)
    }

    // MARK: - Override points: plugins

    /// Plugin classes for this page. Created and attached in order before the first `loadView`.
    ///
    /// ```swift
    /// override func pluginClasses() -> [any KirbyPlugin.Type] {
    ///     [TrackingPlugin.self, LoadingStatePlugin.self]
    /// }
    /// ```
    open func pluginClasses() -> [any KirbyPlugin.Type] { [] }

    /// Plugin classes to attach on the first `viewDidAppear`, for plugins not needed for the first frame.
    ///
    /// They miss the first `viewWillAppear` / `viewIsAppearing` and anything that happened before attaching.
    open func deferredPluginClasses() -> [any KirbyPlugin.Type] { [] }

    // MARK: - Override points: view

    /// Register cells and configure the data source here.
    open func setupUI() {}

    /// Subscribe to context events here. Capture `self` weakly in handlers.
    open func setupEvents() {}

    /// Applies view model state to the views, usually by applying a new snapshot.
    ///
    /// Runs under Observation tracking and is called again when an `@Observable` property read here changes.
    /// Keep it idempotent and cheap. For non-observable state, call ``setNeedsRender()``.
    open func render() {}

    /// Traits forwarded to plugins when they change. Defaults to appearance, size classes and content size.
    open var observedTraits: [UITrait] { KirbySupport.defaultObservedTraits }

    // MARK: - Override points: main request

    /// The page's main request, or `nil` when it has none.
    ///
    /// Sending, cancelling, retrying and notifying plugins is handled by the base class.
    ///
    /// ```swift
    /// override func mainRequest() -> KirbyRequest? {
    ///     KirbyRequest(url: "https://api.example.com/demo/detail", parameters: ["id": context[DemoIDKey.self]])
    /// }
    /// ```
    open func mainRequest() -> KirbyRequest? { nil }

    /// Parses the response and updates the view model. Throwing reports a parsing failure.
    open func handleMainResponse(_ response: KirbyResponse) throws {}

    /// Called when the main request fails. Not called for cancelled requests.
    open func mainRequestDidFail(_ error: KirbyRequestError) {}

    /// Whether the main request starts automatically at the end of `viewDidLoad`. Defaults to `true`.
    open var loadsMainRequestAutomatically: Bool { true }

    /// The performer used to send the request. Defaults to the global one.
    open var requestPerformer: any KirbyRequestPerforming { KirbyRequestConfiguration.defaultPerformer }

    // MARK: - Main request

    /// Whether the main request is in flight.
    public var isLoadingMainRequest: Bool { mainRequestRunner.isLoading }

    /// Starts the main request, cancelling any in-flight one. Does nothing when there is no request.
    public func loadMainRequest() {
        startMainRequest(isRetry: false)
    }

    /// Retries the main request. Plugins see `isRetry == true`.
    public func retryMainRequest() {
        startMainRequest(isRetry: true)
    }

    /// Cancels the in-flight main request without reporting a failure.
    public func cancelMainRequest() {
        mainRequestRunner.cancel()
    }

    // MARK: - render

    /// Schedules a `render()`. Calls are coalesced.
    public func setNeedsRender() {
        if #available(iOS 26, *) {
            setNeedsUpdateProperties()
        } else {
            renderTracker.setNeedsRender()
            Task { @MainActor [weak self] in self?.renderIfNeeded() }
        }
    }

    // MARK: - Lifecycle

    open override func loadView() {
        installPluginsIfNeeded()
        super.loadView()
    }

    open override func viewDidLoad() {
        super.viewDidLoad()
        // Covers subclasses that override loadView without calling super.
        installPluginsIfNeeded()
        setupUI()
        setupEvents()
        registerForTraitChanges(observedTraits) { (self: Self, previous: UITraitCollection) in
            self.pluginHost.traitsDidChange(previous)
        }
        pluginHost.viewDidLoad()
        if loadsMainRequestAutomatically {
            loadMainRequest()
        }
    }

    open override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        pluginHost.viewWillAppear(animated)
    }

    open override func viewIsAppearing(_ animated: Bool) {
        super.viewIsAppearing(animated)
        pluginHost.viewIsAppearing(animated)
    }

    open override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        installDeferredPluginsIfNeeded()
        pluginHost.viewDidAppear(animated)
    }

    open override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        pluginHost.viewWillDisappear(animated)
    }

    open override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        pluginHost.viewDidDisappear(animated)
        KirbyLeakDetector.scheduleCheckIfLeaving(self)
    }

    open override func viewWillLayoutSubviews() {
        super.viewWillLayoutSubviews()
        if !KirbySupport.rendersInUpdateProperties {
            renderIfNeeded()
        }
        pluginHost.viewWillLayoutSubviews()
    }

    open override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        pluginHost.viewDidLayoutSubviews()
    }

    @available(iOS 26.0, *)
    open override func updateProperties() {
        super.updateProperties()
        render()
    }

    // MARK: - Private

    private func startMainRequest(isRetry: Bool) {
        guard let request = mainRequest() else { return }
        mainRequestRunner.run(
            request,
            isRetry: isRetry,
            performer: requestPerformer,
            pluginHost: pluginHost,
            parse: { [weak self] response in try self?.handleMainResponse(response) },
            fail: { [weak self] error in self?.mainRequestDidFail(error) }
        )
    }

    /// Render entry point before iOS 26: first from layout, afterwards directly from state changes.
    private func renderIfNeeded() {
        guard isViewLoaded else { return }
        renderTracker.renderIfNeeded({ render() }, onInvalidate: { [weak self] in
            self?.renderIfNeeded()
        })
    }

    private func installPluginsIfNeeded() {
        guard !hasInstalledPlugins else { return }
        hasInstalledPlugins = true
        pluginHost.add(classes: pluginClasses())
    }

    private func installDeferredPluginsIfNeeded() {
        guard !hasInstalledDeferredPlugins else { return }
        hasInstalledDeferredPlugins = true
        pluginHost.add(classes: deferredPluginClasses())
    }
}
