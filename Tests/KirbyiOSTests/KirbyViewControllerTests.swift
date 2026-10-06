import Foundation
import Observation
import Testing
import UIKit
@testable import KirbyiOS
@testable import WildFunctionKit

@MainActor @Observable
private final class TitleViewModel: KirbyViewModel {
    var title = "initial"
    var unrelated = 0
}

private enum EventName {
    static let refresh = "refresh"
}

@MainActor
private class RecordingPage: KirbyViewController {
    let recorder: CallRecorder
    let viewModel = TitleViewModel()
    let label = UILabel()
    var eventCount = 0

    init(recorder: CallRecorder, context: KirbyContext? = nil) {
        self.recorder = recorder
        super.init(context: context)
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

    override func setupUI() {
        recorder.add("page.setupUI")
        view.addSubview(label)
    }

    override func setupEvents() {
        recorder.add("page.setupEvents")
        context.event.subscribe(EventName.refresh) { [weak self] _ in self?.eventCount += 1 }
    }

    override func render() {
        recorder.add("page.render")
        label.text = viewModel.title
    }
}

/// A page that overrides loadView without calling super.
private final class CustomViewPage: RecordingPage {
    override func loadView() {
        view = UIView()
    }
}

@MainActor
@Suite("KirbyViewController")
struct KirbyViewControllerTests {
    private let recorder = CallRecorder()

    @Test("init sets up the context without loading the view or creating plugins")
    func initDoesNotLoadView() {
        let page = RecordingPage(recorder: recorder)
        #expect(page.context.host === page)
        #expect(page.pluginHost.context === page.context)
        #expect(!page.isViewLoaded)
        #expect(recorder.calls.isEmpty)
    }

    @Test("Lifecycle order")
    func lifecycleOrder() async {
        let page = RecordingPage(recorder: recorder)
        let window = TestWindow.show(page)
        #expect(await waitUntil { recorder.index(of: "plugin.viewDidAppear") != nil })

        // The loadView → viewDidLoad segment is fully deterministic.
        #expect(Array(recorder.calls.prefix(5)) == [
            "page.pluginClasses", "plugin.didAttach", "page.setupUI", "page.setupEvents", "plugin.viewDidLoad",
        ])

        let ordered = [
            "plugin.viewDidLoad", "plugin.viewWillAppear", "plugin.viewIsAppearing", "plugin.viewDidAppear",
        ].map { recorder.index(of: $0) }
        #expect(ordered.allSatisfy { $0 != nil })
        #expect(ordered.compactMap { $0 } == ordered.compactMap { $0 }.sorted())

        // render runs at least once after viewDidLoad and before the first layout finishes.
        let render = recorder.index(of: "page.render")
        let didLayout = recorder.index(of: "plugin.viewDidLayoutSubviews")
        let didLoad = recorder.index(of: "plugin.viewDidLoad")
        #expect(render != nil && didLayout != nil && didLoad != nil)
        if let render, let didLayout, let didLoad {
            #expect(didLoad < render)
            #expect(render < didLayout)
        }
        #expect(recorder.index(of: "plugin.viewWillLayoutSubviews") != nil)
        #expect(page.label.text == "initial")

        // One-time callbacks happen once.
        for call in ["page.pluginClasses", "plugin.didAttach", "page.setupUI", "page.setupEvents", "plugin.viewDidLoad"] {
            #expect(recorder.count(of: call) == 1)
        }

        recorder.calls = []
        TestWindow.clear(window)
        #expect(await waitUntil { recorder.index(of: "plugin.viewDidDisappear") != nil })
        let willDisappear = recorder.index(of: "plugin.viewWillDisappear")
        let didDisappear = recorder.index(of: "plugin.viewDidDisappear")
        #expect(willDisappear != nil)
        if let willDisappear, let didDisappear {
            #expect(willDisappear < didDisappear)
        }
    }

    @Test("render runs on exactly one path: updateProperties on iOS 26+, layout before")
    func renderRunsOnExactlyOnePath() {
        let page = RecordingPage(recorder: recorder)
        page.loadViewIfNeeded()
        recorder.calls = []

        page.viewWillLayoutSubviews()
        let rendersFromLayout = recorder.count(of: "page.render")
        #expect(recorder.count(of: "plugin.viewWillLayoutSubviews") == 1)

        if #available(iOS 26, *) {
            #expect(KirbySupport.rendersInUpdateProperties)
            #expect(rendersFromLayout == 0)
            page.updateProperties()
            #expect(recorder.count(of: "page.render") == 1)
        } else {
            #expect(!KirbySupport.rendersInUpdateProperties)
            #expect(rendersFromLayout == 1)
            #expect(recorder.index(of: "page.render") == 0)

            // Later layout passes do not render again without a state change.
            page.viewWillLayoutSubviews()
            #expect(recorder.count(of: "page.render") == 1)
        }
    }

    @Test("Re-renders when observed state changes, not for unrelated state")
    func rerendersWhenObservedStateChanges() async {
        let page = RecordingPage(recorder: recorder)
        let window = TestWindow.show(page)
        #expect(await waitUntil { page.label.text == "initial" })

        page.viewModel.title = "updated"
        #expect(await waitUntil { page.label.text == "updated" })

        // Several mutations in one turn coalesce into one render.
        let rendersBeforeBurst = recorder.count(of: "page.render")
        page.viewModel.title = "a"
        page.viewModel.title = "b"
        page.viewModel.title = "c"
        #expect(await waitUntil { page.label.text == "c" })
        #expect(recorder.count(of: "page.render") == rendersBeforeBurst + 1)

        // Properties render never read do not trigger it.
        let renders = recorder.count(of: "page.render")
        page.viewModel.unrelated += 1
        try? await Task.sleep(for: .milliseconds(100))
        #expect(recorder.count(of: "page.render") == renders)
        _ = window
    }

    @Test("setNeedsRender triggers one render")
    func manualInvalidation() async {
        let page = RecordingPage(recorder: recorder)
        let window = TestWindow.show(page)
        #expect(await waitUntil { recorder.count(of: "page.render") >= 1 })
        try? await Task.sleep(for: .milliseconds(50))

        let renders = recorder.count(of: "page.render")
        page.setNeedsRender()
        page.setNeedsRender()
        #expect(await waitUntil { recorder.count(of: "page.render") > renders })
        try? await Task.sleep(for: .milliseconds(50))
        #expect(recorder.count(of: "page.render") == renders + 1)
        _ = window
    }

    @Test("setNeedsRender before the view loads does not load it")
    func manualInvalidationBeforeViewLoads() {
        let page = RecordingPage(recorder: recorder)
        page.setNeedsRender()
        #expect(!page.isViewLoaded)
    }

    @Test("deferredPluginClasses attach once on the first viewDidAppear")
    func deferredPluginsAttachOnFirstAppear() async {
        let page = RecordingPage(recorder: recorder)
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

    @Test("Subscriptions made in setupEvents are delivered")
    func eventsAreDelivered() {
        let page = RecordingPage(recorder: recorder)
        page.loadViewIfNeeded()
        page.context.event.dispatch(EventName.refresh)
        #expect(page.eventCount == 1)
    }

    @Test("Plugins install once even with a custom loadView")
    func pluginsInstalledWithCustomLoadView() {
        let page = CustomViewPage(recorder: recorder)
        page.loadViewIfNeeded()
        #expect(Array(recorder.calls.prefix(5)) == [
            "page.pluginClasses", "plugin.didAttach", "page.setupUI", "page.setupEvents", "plugin.viewDidLoad",
        ])
        #expect(recorder.count(of: "page.pluginClasses") == 1)
    }

    @Test("Plugins added after viewDidLoad get it replayed")
    func latePluginReceivesViewDidLoad() {
        let page = RecordingPage(recorder: recorder)
        page.loadViewIfNeeded()
        recorder.calls = []
        page.pluginHost.add(classes: [LifecyclePlugin.self])
        #expect(recorder.calls == ["plugin.didAttach", "plugin.viewDidLoad"])
    }

    @Test("Observed trait changes are forwarded to plugins")
    func forwardsTraitChanges() async {
        let page = RecordingPage(recorder: recorder)
        #expect(page.observedTraits.count == 4)
        let window = TestWindow.show(page)
        recorder.calls = []

        page.traitOverrides.userInterfaceStyle = page.traitCollection.userInterfaceStyle == .dark ? .light : .dark
        page.updateTraitsIfNeeded()
        #expect(await waitUntil { recorder.index(of: "plugin.traitsDidChange") != nil })
        _ = window
    }

    @Test("Deallocation detaches plugins and clears events without leaking")
    func releasesEverything() async {
        weak var weakPage: RecordingPage?
        weak var weakContext: KirbyContext?
        weak var weakHost: KirbyPluginHost?
        let window: UIWindow
        do {
            let page = RecordingPage(recorder: recorder)
            weakPage = page
            weakContext = page.context
            weakHost = page.pluginHost
            window = TestWindow.show(page)
        }
        #expect(weakPage != nil)

        TestWindow.clear(window)
        #expect(await waitUntil { weakPage == nil })
        #expect(weakContext == nil)
        #expect(weakHost == nil)
        #expect(recorder.count(of: "plugin.willDetach") == 1)
        #expect(recorder.calls.last == "plugin.willDetach")
    }

    @Test("A page that never appeared still detaches its plugins")
    func releasesWithoutEverAppearing() async {
        weak var weakPage: RecordingPage?
        do {
            let page = RecordingPage(recorder: recorder)
            page.loadViewIfNeeded()
            weakPage = page
        }
        #expect(await waitUntil { weakPage == nil })
        #expect(recorder.calls.last == "plugin.willDetach")
    }

    @Test("Default override points are no-ops")
    func defaultHooksAreNoOps() {
        let page = KirbyViewController()
        #expect(page.pluginClasses().isEmpty)
        #expect(page.deferredPluginClasses().isEmpty)
        page.loadViewIfNeeded()
        page.render()
        #expect(page.pluginHost.plugin(ofType: LifecyclePlugin.self) == nil)
    }
}

private struct ParseFailure: Error {}

@MainActor
@Suite("KirbyViewController main request")
struct KirbyViewControllerMainRequestTests {
    private let recorder = CallRecorder()
    private let request = KirbyRequest(url: "https://example.com/detail", parameters: ["id": 1])

    private func makePage() -> RecordingPage {
        let page = RecordingPage(recorder: recorder)
        page.request = request
        return page
    }

    /// Only the main-request calls, to assert their order.
    private var requestCalls: [String] {
        recorder.calls.filter { $0.contains("ainRequest") || $0.contains("handleMainResponse") }
    }

    @Test("Starts after viewDidLoad and reports willSend, didReceive, parse, didParse")
    func automaticLoadSucceeds() async {
        let page = makePage()
        page.loadViewIfNeeded()
        #expect(page.isLoadingMainRequest)
        #expect(recorder.calls.suffix(2) == ["plugin.viewDidLoad", "plugin.mainRequestWillSend(retry: false)"])

        #expect(await waitUntil { !page.isLoadingMainRequest })
        #expect(requestCalls == [
            "plugin.mainRequestWillSend(retry: false)",
            "plugin.mainRequestDidReceive",
            "page.handleMainResponse",
            "plugin.mainRequestDidParse",
        ])
    }

    @Test("A page without a main request triggers no callbacks")
    func noRequest() async {
        let page = RecordingPage(recorder: recorder)
        page.loadViewIfNeeded()
        page.loadMainRequest()
        page.retryMainRequest()
        try? await Task.sleep(for: .milliseconds(50))
        #expect(!page.isLoadingMainRequest)
        #expect(requestCalls.isEmpty)
    }

    @Test("A failed request reports didFail to plugins and the page without parsing")
    func requestFails() async {
        let page = makePage()
        page.performer.outcome = .failure(.httpStatus(500))
        page.loadViewIfNeeded()
        #expect(await waitUntil { !page.isLoadingMainRequest })
        #expect(requestCalls == [
            "plugin.mainRequestWillSend(retry: false)",
            "plugin.mainRequestDidFail(httpStatus(500))",
            "page.mainRequestDidFail(httpStatus(500))",
        ])
    }

    @Test("A throwing parse step reports a parsing failure")
    func parsingFails() async {
        let page = makePage()
        page.parseError = ParseFailure()
        page.loadViewIfNeeded()
        #expect(await waitUntil { !page.isLoadingMainRequest })
        #expect(requestCalls == [
            "plugin.mainRequestWillSend(retry: false)",
            "plugin.mainRequestDidReceive",
            "page.handleMainResponse",
            "plugin.mainRequestDidFail(parsing(\"ParseFailure()\"))",
            "page.mainRequestDidFail(parsing(\"ParseFailure()\"))",
        ])
    }

    @Test("Unexpected performer errors map to transport")
    func unexpectedErrorIsMappedToTransport() async {
        let page = makePage()
        page.performer.outcome = .unexpectedError
        page.loadViewIfNeeded()
        #expect(await waitUntil { !page.isLoadingMainRequest })
        #expect(requestCalls.last?.hasPrefix("page.mainRequestDidFail(transport(") == true)
    }

    @Test("Retry reports isRetry = true")
    func retry() async {
        let page = makePage()
        page.performer.outcome = .failure(.transport("offline"))
        page.loadViewIfNeeded()
        #expect(await waitUntil { !page.isLoadingMainRequest })

        recorder.calls = []
        page.performer.outcome = .success(KirbyResponse(data: Data()))
        page.retryMainRequest()
        #expect(await waitUntil { !page.isLoadingMainRequest })
        #expect(requestCalls == [
            "plugin.mainRequestWillSend(retry: true)",
            "plugin.mainRequestDidReceive",
            "page.handleMainResponse",
            "plugin.mainRequestDidParse",
        ])
    }

    @Test("With automatic loading off, only manual calls start a request")
    func manualLoad() async {
        let page = makePage()
        page.autoLoads = false
        page.loadViewIfNeeded()
        #expect(!page.isLoadingMainRequest)
        #expect(requestCalls.isEmpty)

        page.loadMainRequest()
        #expect(await waitUntil { !page.isLoadingMainRequest })
        #expect(requestCalls.last == "plugin.mainRequestDidParse")
    }

    @Test("A new request cancels the previous one silently")
    func newRequestCancelsPrevious() async {
        let page = makePage()
        page.performer.delay = .milliseconds(80)
        page.loadViewIfNeeded()
        page.loadMainRequest()
        #expect(await waitUntil { !page.isLoadingMainRequest })
        try? await Task.sleep(for: .milliseconds(120))

        #expect(recorder.count(of: "plugin.mainRequestWillSend(retry: false)") == 2)
        #expect(recorder.count(of: "page.handleMainResponse") == 1)
        #expect(recorder.count(of: "plugin.mainRequestDidParse") == 1)
        #expect(!requestCalls.contains { $0.contains("DidFail") })
    }

    @Test("cancelMainRequest stops all further callbacks")
    func cancel() async {
        let page = makePage()
        page.performer.delay = .milliseconds(50)
        page.loadViewIfNeeded()
        page.cancelMainRequest()
        #expect(!page.isLoadingMainRequest)

        try? await Task.sleep(for: .milliseconds(120))
        #expect(requestCalls == ["plugin.mainRequestWillSend(retry: false)"])
    }

    @Test("A performer reporting cancelled is not a failure")
    func performerReportsCancelled() async {
        let page = makePage()
        page.performer.outcome = .failure(.cancelled)
        page.loadViewIfNeeded()
        #expect(await waitUntil { !page.isLoadingMainRequest })
        #expect(requestCalls == ["plugin.mainRequestWillSend(retry: false)"])
    }

    @Test("Releasing the page mid-request neither leaks nor calls back")
    func pageReleasedWhileLoading() async {
        weak var weakPage: RecordingPage?
        do {
            let page = makePage()
            page.performer.delay = .milliseconds(50)
            page.loadViewIfNeeded()
            weakPage = page
        }
        // The request task may hold a reference briefly as it starts, so wait before asserting.
        #expect(await waitUntil { weakPage == nil })
        try? await Task.sleep(for: .milliseconds(120))
        #expect(!requestCalls.contains("page.handleMainResponse"))
        #expect(!requestCalls.contains { $0.contains("DidFail") })
    }

    @Test("Uses the global performer by default")
    func defaultPerformer() {
        let page = KirbyViewController()
        #expect(page.requestPerformer is DefaultRequestPerformer)
        #expect(page.loadsMainRequestAutomatically)
        #expect(page.mainRequest() == nil)
        #expect(throws: Never.self) { try page.handleMainResponse(KirbyResponse(data: Data())) }
        page.mainRequestDidFail(.cancelled)
    }
}

@MainActor
@Suite("KirbyViewController shared context")
struct KirbyViewControllerSharedContextTests {
    private let recorder = CallRecorder()

    @Test("A child given the parent's context shares its event center")
    func childSharesParentContext() {
        let parent = RecordingPage(recorder: recorder)
        let child = RecordingPage(recorder: recorder, context: parent.context)
        parent.loadViewIfNeeded()
        child.loadViewIfNeeded()

        #expect(child.context === parent.context)
        #expect(parent.context.host === parent)
        #expect(child.pluginHost !== parent.pluginHost)

        child.context.event.dispatch(EventName.refresh)
        #expect(parent.eventCount == 1)
        #expect(child.eventCount == 1)
    }

    @Test("Releasing a child keeps the parent's subscriptions")
    func childDeinitKeepsParentSubscriptions() async {
        let parent = RecordingPage(recorder: recorder)
        parent.loadViewIfNeeded()
        weak var weakChild: RecordingPage?
        do {
            let child = RecordingPage(recorder: recorder, context: parent.context)
            child.loadViewIfNeeded()
            weakChild = child
        }
        #expect(await waitUntil { weakChild == nil })

        parent.context.event.dispatch(EventName.refresh)
        #expect(parent.eventCount == 1)
    }
}

@MainActor
@Suite("KirbyLeakDetector")
struct KirbyLeakDetectorTests {
    @Test("Reports a page that is still alive after leaving the screen")
    func reportsRetainedPage() async {
        let leaked = KirbyViewController()
        var reported: [String] = []
        await KirbyLeakDetector.scheduleCheck(for: leaked, after: .milliseconds(20)) { reported.append($0) }.value
        #expect(reported == ["KirbyViewController"])
    }

    @Test("Does not report a released page")
    func ignoresReleasedPage() async {
        var reported: [String] = []
        let task: Task<Void, Never>
        do {
            let page = KirbyViewController()
            task = KirbyLeakDetector.scheduleCheck(for: page, after: .milliseconds(20)) { reported.append($0) }
        }
        await task.value
        #expect(reported.isEmpty)
    }

    @Test("Does not report a page still in the hierarchy")
    func ignoresAttachedPage() async {
        let page = KirbyViewController()
        let navigation = UINavigationController(rootViewController: page)
        var reported: [String] = []
        await KirbyLeakDetector.scheduleCheck(for: page, after: .milliseconds(20)) { reported.append($0) }.value
        #expect(reported.isEmpty)
        _ = navigation
    }

    @Test("scheduleCheckIfLeaving is safe to call")
    func scheduleIfLeavingIsSafe() {
        let page = KirbyViewController()
        KirbyLeakDetector.scheduleCheckIfLeaving(page)
        #expect(KirbyLeakDetector.defaultDelay == .seconds(2))
    }
}
