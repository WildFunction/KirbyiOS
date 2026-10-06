import Foundation
import Observation
import Testing
import UIKit
@testable import KirbyiOS
@testable import WildFunctionKit

@MainActor @Observable
private final class ItemsViewModel: KirbyViewModel {
    var items: [Int] = []
}

@MainActor
private final class RecordingListPage: KirbyCollectionViewController {
    let recorder: CallRecorder
    let viewModel = ItemsViewModel()
    var renderedItems: [Int] = []

    init(recorder: CallRecorder, context: KirbyContext? = nil) {
        self.recorder = recorder
        super.init(collectionViewLayout: UICollectionViewFlowLayout(), context: context)
        self.context[CallRecorderKey.self] = recorder
    }

    override func pluginClasses() -> [any KirbyPlugin.Type] {
        recorder.add("page.pluginClasses")
        return [LifecyclePlugin.self]
    }

    override func deferredPluginClasses() -> [any KirbyPlugin.Type] {
        recorder.add("page.deferredPluginClasses")
        return [DeferredLifecyclePlugin.self]
    }

    // Main request: none by default; each test configures what it needs.
    var request: KirbyRequest?
    var performer = StubPerformer()
    var autoLoads = true
    var parseError: (any Error)?

    override func mainRequest() -> KirbyRequest? { request }
    override var requestPerformer: any KirbyRequestPerforming { performer }
    override var loadsMainRequestAutomatically: Bool { autoLoads }

    override func handleMainResponse(_ response: KirbyResponse) throws {
        recorder.add("page.handleMainResponse")
        if let parseError { throw parseError }
    }

    override func mainRequestDidFail(_ error: KirbyRequestError) {
        recorder.add("page.mainRequestDidFail(\(error))")
    }

    override func setupUI() { recorder.add("page.setupUI") }
    override func setupEvents() { recorder.add("page.setupEvents") }
    override func render() {
        recorder.add("page.render")
        renderedItems = viewModel.items
    }
}

@MainActor
@Suite("KirbyCollectionViewController")
struct KirbyCollectionViewControllerTests {
    private let recorder = CallRecorder()

    @Test("init sets up the context without loading the view")
    func initDoesNotLoadView() {
        let page = RecordingListPage(recorder: recorder)
        #expect(page.context.host === page)
        #expect(page.pluginHost.context === page.context)
        #expect(!page.isViewLoaded)
        #expect(recorder.calls.isEmpty)
        #expect(page.observedTraits.count == 4)
    }

    @Test("Lifecycle order matches KirbyViewController")
    func lifecycleOrder() async {
        let page = RecordingListPage(recorder: recorder)
        let window = TestWindow.show(page)
        #expect(await waitUntil { recorder.index(of: "plugin.viewDidAppear") != nil })

        #expect(Array(recorder.calls.prefix(5)) == [
            "page.pluginClasses", "plugin.didAttach", "page.setupUI", "page.setupEvents", "plugin.viewDidLoad",
        ])
        let ordered = [
            "plugin.viewDidLoad", "plugin.viewWillAppear", "plugin.viewIsAppearing", "plugin.viewDidAppear",
        ].compactMap { recorder.index(of: $0) }
        #expect(ordered.count == 4)
        #expect(ordered == ordered.sorted())
        #expect(recorder.index(of: "page.render") != nil)
        #expect(recorder.index(of: "plugin.viewWillLayoutSubviews") != nil)
        #expect(recorder.index(of: "plugin.viewDidLayoutSubviews") != nil)
        #expect(page.collectionView != nil)

        recorder.calls = []
        TestWindow.clear(window)
        #expect(await waitUntil { recorder.index(of: "plugin.viewDidDisappear") != nil })
        #expect(recorder.index(of: "plugin.viewWillDisappear") != nil)
    }

    @Test("render runs on exactly one path")
    func renderRunsOnExactlyOnePath() {
        let page = RecordingListPage(recorder: recorder)
        page.loadViewIfNeeded()
        recorder.calls = []

        page.viewWillLayoutSubviews()
        if #available(iOS 26, *) {
            #expect(recorder.count(of: "page.render") == 0)
            page.updateProperties()
            #expect(recorder.count(of: "page.render") == 1)
        } else {
            #expect(recorder.count(of: "page.render") == 1)
            page.viewWillLayoutSubviews()
            #expect(recorder.count(of: "page.render") == 1)
        }
    }

    @Test("Re-renders when observed state changes or setNeedsRender is called")
    func rerendersWhenObservedStateChanges() async {
        let page = RecordingListPage(recorder: recorder)
        page.setNeedsRender()
        #expect(!page.isViewLoaded)

        let window = TestWindow.show(page)
        #expect(await waitUntil { recorder.count(of: "page.render") >= 1 })

        page.viewModel.items = [1, 2, 3]
        #expect(await waitUntil { page.renderedItems == [1, 2, 3] })

        try? await Task.sleep(for: .milliseconds(50))
        let renders = recorder.count(of: "page.render")
        page.setNeedsRender()
        #expect(await waitUntil { recorder.count(of: "page.render") == renders + 1 })
        _ = window
    }

    @Test("deferredPluginClasses attach once on the first viewDidAppear")
    func deferredPluginsAttachOnFirstAppear() async {
        let page = RecordingListPage(recorder: recorder)
        page.loadViewIfNeeded()
        #expect(recorder.index(of: "page.deferredPluginClasses") == nil)

        let window = TestWindow.show(page)
        #expect(await waitUntil { recorder.index(of: "deferred.viewDidAppear") != nil })

        // Gets didAttach, a replayed viewDidLoad and this viewDidAppear, but no earlier appear callbacks.
        let deferredCalls = recorder.calls.filter { $0.hasPrefix("deferred.") && !$0.contains("Layout") }
        #expect(deferredCalls == ["deferred.didAttach", "deferred.viewDidLoad", "deferred.viewDidAppear"])
        #expect(recorder.index(of: "plugin.viewWillAppear") ?? .max < recorder.index(of: "page.deferredPluginClasses") ?? .min)

        // Appearing again does not create them twice.
        page.viewDidAppear(false)
        #expect(recorder.count(of: "page.deferredPluginClasses") == 1)
        #expect(recorder.count(of: "deferred.didAttach") == 1)
        #expect(recorder.count(of: "deferred.viewDidAppear") == 2)
        _ = window
    }

    @Test("Main request starts automatically and reports success and failure in order")
    func mainRequest() async {
        let page = RecordingListPage(recorder: recorder)
        page.request = KirbyRequest(url: "https://example.com/list")
        page.loadViewIfNeeded()
        #expect(page.isLoadingMainRequest)
        #expect(await waitUntil { !page.isLoadingMainRequest })

        let succeeded = recorder.calls.filter { $0.contains("ainRequest") || $0.contains("handleMainResponse") }
        #expect(succeeded == [
            "plugin.mainRequestWillSend(retry: false)",
            "plugin.mainRequestDidReceive",
            "page.handleMainResponse",
            "plugin.mainRequestDidParse",
        ])

        recorder.calls = []
        page.performer.outcome = .failure(.httpStatus(503))
        page.retryMainRequest()
        #expect(await waitUntil { !page.isLoadingMainRequest })
        #expect(recorder.calls == [
            "plugin.mainRequestWillSend(retry: true)",
            "plugin.mainRequestDidFail(httpStatus(503))",
            "page.mainRequestDidFail(httpStatus(503))",
        ])

        page.performer.delay = .milliseconds(50)
        page.loadMainRequest()
        page.cancelMainRequest()
        #expect(!page.isLoadingMainRequest)
    }

    @Test("Shares the parent page's context")
    func sharesContext() {
        let parent = KirbyViewController()
        let child = RecordingListPage(recorder: recorder, context: parent.context)
        #expect(child.context === parent.context)
        #expect(parent.context.host === parent)
    }

    @Test("Trait changes are forwarded to plugins")
    func forwardsTraitChanges() async {
        let page = RecordingListPage(recorder: recorder)
        let window = TestWindow.show(page)
        recorder.calls = []
        page.traitOverrides.userInterfaceStyle = page.traitCollection.userInterfaceStyle == .dark ? .light : .dark
        page.updateTraitsIfNeeded()
        #expect(await waitUntil { recorder.index(of: "plugin.traitsDidChange") != nil })
        _ = window
    }

    @Test("Deallocation detaches plugins without leaking")
    func releasesEverything() async {
        weak var weakPage: RecordingListPage?
        weak var weakContext: KirbyContext?
        let window: UIWindow
        do {
            let page = RecordingListPage(recorder: recorder)
            weakPage = page
            weakContext = page.context
            window = TestWindow.show(page)
        }
        TestWindow.clear(window)
        #expect(await waitUntil { weakPage == nil })
        #expect(weakContext == nil)
        #expect(recorder.calls.last == "plugin.willDetach")
    }

    @Test("Default override points are no-ops")
    func defaultHooksAreNoOps() {
        let page = KirbyCollectionViewController(collectionViewLayout: UICollectionViewFlowLayout())
        #expect(page.pluginClasses().isEmpty)
        #expect(page.deferredPluginClasses().isEmpty)
        #expect(page.mainRequest() == nil)
        #expect(page.loadsMainRequestAutomatically)
        #expect(page.requestPerformer is DefaultRequestPerformer)
        #expect(throws: Never.self) { try page.handleMainResponse(KirbyResponse(data: Data())) }
        page.mainRequestDidFail(.cancelled)
        page.loadViewIfNeeded()
        page.render()
    }
}
