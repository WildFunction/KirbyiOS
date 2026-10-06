import Foundation
import Testing
import UIKit
@testable import KirbyiOS
@testable import WildFunctionKit

@MainActor
private final class Recorder {
    var calls: [String] = []
    func add(_ call: String) { calls.append(call) }
}

/// Plugins are created with `init()`, so tests hand them the recorder through the context.
private enum RecorderKey: KirbyContextKey {
    static var defaultValue: Recorder? { nil }
}

/// Test plugin that records every callback.
@MainActor
private class RecordingPlugin: KirbyPlugin {
    class var label: String { "p" }
    var name: String
    var recorder: Recorder?
    var onViewWillAppear: (() -> Void)?

    required init() {
        name = Self.label
    }

    convenience init(_ name: String, recorder: Recorder) {
        self.init()
        self.name = name
        self.recorder = recorder
    }

    private func record(_ method: String) { recorder?.add("\(name).\(method)") }

    func didAttach(to context: KirbyContext) {
        recorder = recorder ?? context[RecorderKey.self]
        record("didAttach")
    }
    func willDetach(from context: KirbyContext) { record("willDetach") }
    func viewDidLoad() { record("viewDidLoad") }
    func viewWillAppear(_ animated: Bool) {
        record("viewWillAppear")
        onViewWillAppear?()
    }
    func viewIsAppearing(_ animated: Bool) { record("viewIsAppearing") }
    func viewDidAppear(_ animated: Bool) { record("viewDidAppear") }
    func viewWillDisappear(_ animated: Bool) { record("viewWillDisappear") }
    func viewDidDisappear(_ animated: Bool) { record("viewDidDisappear") }
    func viewWillLayoutSubviews() { record("viewWillLayoutSubviews") }
    func viewDidLayoutSubviews() { record("viewDidLayoutSubviews") }
    func traitsDidChange(_ previous: UITraitCollection) { record("traitsDidChange") }
    func mainRequestWillSend(_ request: KirbyRequest, isRetry: Bool) { record("mainRequestWillSend(retry: \(isRetry))") }
    func mainRequestDidReceive(_ response: KirbyResponse) { record("mainRequestDidReceive(\(response.statusCode))") }
    func mainRequestDidParse(_ response: KirbyResponse) { record("mainRequestDidParse") }
    func mainRequestDidFail(_ error: KirbyRequestError) { record("mainRequestDidFail(\(error))") }
}

private final class FirstPlugin: RecordingPlugin {
    override class var label: String { "first" }
}

private final class SecondPlugin: RecordingPlugin {
    override class var label: String { "second" }
}

/// Conforms without overriding anything, to exercise the defaults.
@MainActor
private final class EmptyPlugin: KirbyPlugin {
    init() {}
}

private enum EventName {
    static let tick = "tick"
    static let label = "label"
}

@MainActor
@Suite("KirbyPluginHost")
struct KirbyPluginHostTests {
    private let context = KirbyContext()
    private let recorder = Recorder()
    private let host: KirbyPluginHost

    init() {
        context[RecorderKey.self] = recorder
        host = KirbyPluginHost(context: context)
    }

    private func plugin(_ name: String) -> RecordingPlugin {
        RecordingPlugin(name, recorder: recorder)
    }

    // MARK: Creation and order

    @Test("add(classes:) creates and attaches in list order")
    func createsPluginsFromClasses() {
        host.add(classes: [SecondPlugin.self, FirstPlugin.self])
        #expect(recorder.calls == ["second.didAttach", "first.didAttach"])
        #expect(host.plugin(ofType: FirstPlugin.self) != nil)
        #expect(host.plugin(ofType: SecondPlugin.self) != nil)

        recorder.calls = []
        host.viewWillAppear(true)
        #expect(recorder.calls == ["second.viewWillAppear", "first.viewWillAppear"])
    }

    @Test("Forwards in insertion order")
    func forwardsInInsertionOrder() {
        host.add([plugin("a"), plugin("b"), plugin("c")])
        recorder.calls = []
        host.viewWillAppear(true)
        #expect(recorder.calls == ["a", "b", "c"].map { "\($0).viewWillAppear" })
    }

    @Test("Forwards every view lifecycle method")
    func forwardsEveryViewLifecycleMethod() {
        host.add(plugin("p"))
        recorder.calls = []

        host.viewDidLoad()
        host.viewWillAppear(false)
        host.viewIsAppearing(false)
        host.viewDidAppear(false)
        host.viewWillLayoutSubviews()
        host.viewDidLayoutSubviews()
        host.traitsDidChange(UITraitCollection())
        host.viewWillDisappear(false)
        host.viewDidDisappear(false)

        #expect(recorder.calls == [
            "viewDidLoad", "viewWillAppear", "viewIsAppearing", "viewDidAppear",
            "viewWillLayoutSubviews", "viewDidLayoutSubviews", "traitsDidChange",
            "viewWillDisappear", "viewDidDisappear",
        ].map { "p.\($0)" })
    }

    @Test("Forwards every main request stage")
    func forwardsMainRequestLifecycle() {
        host.add([plugin("a"), plugin("b")])
        recorder.calls = []
        let request = KirbyRequest(url: "https://example.com")
        let response = KirbyResponse(data: Data(), statusCode: 201)

        host.mainRequestWillSend(request, isRetry: false)
        host.mainRequestDidReceive(response)
        host.mainRequestDidParse(response)
        host.mainRequestWillSend(request, isRetry: true)
        host.mainRequestDidFail(.httpStatus(500))

        #expect(recorder.calls == [
            "a.mainRequestWillSend(retry: false)", "b.mainRequestWillSend(retry: false)",
            "a.mainRequestDidReceive(201)", "b.mainRequestDidReceive(201)",
            "a.mainRequestDidParse", "b.mainRequestDidParse",
            "a.mainRequestWillSend(retry: true)", "b.mainRequestWillSend(retry: true)",
            "a.mainRequestDidFail(httpStatus(500))", "b.mainRequestDidFail(httpStatus(500))",
        ])
    }

    // MARK: Snapshot

    @Test("Forwarding uses a snapshot of the plugin list")
    func forwardingUsesSnapshot() {
        let first = plugin("first")
        let second = plugin("second")
        let late = plugin("late")
        first.onViewWillAppear = { [host] in
            host.remove(second)
            host.add(late)
        }
        host.add([first, second])
        recorder.calls = []

        host.viewWillAppear(true)
        #expect(recorder.calls == [
            "first.viewWillAppear", "second.willDetach", "late.didAttach", "second.viewWillAppear",
        ])

        first.onViewWillAppear = nil
        recorder.calls = []
        host.viewWillAppear(true)
        #expect(recorder.calls == ["first.viewWillAppear", "late.viewWillAppear"])
    }

    // MARK: Replay

    @Test("Late plugins get viewDidLoad replayed but no appear events")
    func latePluginReceivesViewDidLoadOnly() {
        host.viewDidLoad()
        host.viewWillAppear(true)
        host.viewIsAppearing(true)
        host.viewDidAppear(true)

        host.add(plugin("late"))
        #expect(recorder.calls == ["late.didAttach", "late.viewDidLoad"])
    }

    @Test("Early plugins receive viewDidLoad once")
    func earlyPluginReceivesViewDidLoadOnce() {
        host.add(plugin("early"))
        host.viewDidLoad()
        #expect(recorder.calls == ["early.didAttach", "early.viewDidLoad"])
    }

    // MARK: detach

    @Test("detachAll runs in reverse insertion order")
    func detachAllRunsInReverseInsertionOrder() {
        host.add([plugin("a"), plugin("b"), plugin("c")])
        recorder.calls = []

        host.detachAll()
        #expect(recorder.calls == ["c.willDetach", "b.willDetach", "a.willDetach"])

        recorder.calls = []
        host.detachAll()
        host.viewWillAppear(true)
        #expect(recorder.calls.isEmpty)
    }

    @Test("remove detaches the plugin")
    func removeDetachesPlugin() {
        let removed = plugin("removed")
        host.add([removed, plugin("kept")])
        recorder.calls = []

        host.remove(removed)
        host.remove(removed)
        host.viewDidAppear(true)
        #expect(recorder.calls == ["removed.willDetach", "kept.viewDidAppear"])
    }

    // MARK: Slow calls

    @Test("Slow calls are reported with plugin type and method in DEBUG")
    func reportsSlowCalls() {
        var reported: [KirbyPluginHost.SlowCall] = []
        host.onSlowCall = { reported.append($0) }
        #expect(host.slowCallThreshold == .milliseconds(16))

        let slow = plugin("slow")
        slow.onViewWillAppear = { Thread.sleep(forTimeInterval: 0.03) }
        host.add([slow, plugin("fast")])

        host.viewWillAppear(true)
        host.viewDidAppear(true)

        #expect(reported.count == 1)
        #expect(reported.first?.pluginType == "RecordingPlugin")
        #expect(reported.first?.method == "viewWillAppear")
        #expect((reported.first?.duration ?? .zero) > .milliseconds(16))
    }

    @Test("The default slow-call handler only logs")
    func defaultSlowCallHandler() {
        host.slowCallThreshold = .zero
        host.add(plugin("p"))
        host.viewWillAppear(true)
    }

    // MARK: Misc

    @Test("Duplicate instances are ignored")
    func ignoresDuplicateInstances() {
        let single = plugin("single")
        host.add(single)
        host.add(single)
        host.viewDidLoad()
        #expect(recorder.calls == ["single.didAttach", "single.viewDidLoad"])
    }

    @Test("plugin(ofType:) finds by type")
    func findsPluginByType() {
        let first = FirstPlugin("first", recorder: recorder)
        host.add([plugin("plain"), first])
        #expect(host.plugin(ofType: FirstPlugin.self) === first)
        #expect(host.plugin(ofType: RecordingPlugin.self)?.name == "plain")
        #expect(host.plugin(ofType: EmptyPlugin.self) == nil)
    }

    @Test("Protocol defaults are no-ops")
    func protocolDefaults() {
        host.add(classes: [EmptyPlugin.self])
        host.viewDidLoad()
        host.viewWillAppear(true)
        host.viewIsAppearing(true)
        host.viewDidAppear(true)
        host.viewWillLayoutSubviews()
        host.viewDidLayoutSubviews()
        host.traitsDidChange(UITraitCollection())
        host.viewWillDisappear(true)
        host.viewDidDisappear(true)
        host.mainRequestWillSend(KirbyRequest(url: "https://example.com"), isRetry: false)
        host.mainRequestDidReceive(KirbyResponse(data: Data()))
        host.mainRequestDidParse(KirbyResponse(data: Data()))
        host.mainRequestDidFail(.cancelled)
        host.detachAll()
        #expect(host.plugin(ofType: EmptyPlugin.self) == nil)
    }

    @Test("Deallocation detaches everything without leaking")
    func releasesEverythingOnDeinit() {
        let localRecorder = Recorder()
        weak var weakHost: KirbyPluginHost?
        weak var weakPlugin: RecordingPlugin?
        weak var weakContext: KirbyContext?
        do {
            let localContext = KirbyContext()
            let localHost = KirbyPluginHost(context: localContext)
            let local = RecordingPlugin("p", recorder: localRecorder)
            localHost.add(local)
            weakHost = localHost
            weakPlugin = local
            weakContext = localContext
        }
        #expect(weakHost == nil)
        #expect(weakPlugin == nil)
        #expect(weakContext == nil)
        #expect(localRecorder.calls == ["p.didAttach", "p.willDetach"])
    }
}

@MainActor
@Suite("BaseKirbyPlugin")
struct BasePagePluginTests {
    private final class CountingPlugin: BaseKirbyPlugin {
        var ticks = 0
        var labels: [String] = []

        override func didAttach(to context: KirbyContext) {
            super.didAttach(to: context)
            observe(EventName.tick) { [weak self] _ in self?.ticks += 1 }
            observe(EventName.label, as: String.self) { [weak self] label in self?.labels.append(label) }
        }
    }

    @Test("Keeps the context and cancels observe subscriptions on detach")
    func managesContextAndSubscriptions() throws {
        let context = KirbyContext()
        let host = KirbyPluginHost(context: context)
        host.add(classes: [CountingPlugin.self])
        let plugin = try #require(host.plugin(ofType: CountingPlugin.self))
        #expect(plugin.context === context)

        context.event.dispatch(EventName.tick)
        context.event.dispatch(EventName.label, "a")
        context.event.dispatch(EventName.label, 1)
        #expect(plugin.ticks == 1)
        #expect(plugin.labels == ["a"])

        host.remove(plugin)
        #expect(plugin.context == nil)
        context.event.dispatch(EventName.tick)
        context.event.dispatch(EventName.label, "b")
        #expect(plugin.ticks == 1)
        #expect(plugin.labels == ["a"])
    }

    @Test("observe before attaching is ignored")
    func observeBeforeAttachIsIgnored() {
        let plugin = CountingPlugin()
        plugin.observe(EventName.tick) { _ in }
        plugin.observe(EventName.label, as: String.self) { _ in }
        #expect(plugin.context == nil)
    }

    @Test("Base lifecycle methods are no-ops")
    func baseImplementationsAreNoOps() {
        let plugin = BaseKirbyPlugin()
        plugin.viewDidLoad()
        plugin.viewWillAppear(true)
        plugin.viewIsAppearing(true)
        plugin.viewDidAppear(true)
        plugin.viewWillDisappear(true)
        plugin.viewDidDisappear(true)
        plugin.viewWillLayoutSubviews()
        plugin.viewDidLayoutSubviews()
        plugin.traitsDidChange(UITraitCollection())
        plugin.mainRequestWillSend(KirbyRequest(url: "https://example.com"), isRetry: false)
        plugin.mainRequestDidReceive(KirbyResponse(data: Data()))
        plugin.mainRequestDidParse(KirbyResponse(data: Data()))
        plugin.mainRequestDidFail(.cancelled)
        #expect(plugin.context == nil)
    }

    @Test("The context reference is weak")
    func contextReferenceIsWeak() {
        let plugin = CountingPlugin()
        weak var weakContext: KirbyContext?
        do {
            let context = KirbyContext()
            weakContext = context
            plugin.didAttach(to: context)
        }
        #expect(weakContext == nil)
        #expect(plugin.context == nil)
    }
}
