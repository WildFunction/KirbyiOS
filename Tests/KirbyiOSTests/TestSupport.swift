import UIKit
@testable import KirbyiOS
@testable import WildFunctionKit

@MainActor
final class CallRecorder {
    var calls: [String] = []
    func add(_ call: String) { calls.append(call) }
    func index(of call: String) -> Int? { calls.firstIndex(of: call) }
    func count(of call: String) -> Int { calls.count { $0 == call } }
}

/// Plugins are created with `init()`, so test pages hand them the recorder through the context.
enum CallRecorderKey: KirbyContextKey {
    static var defaultValue: CallRecorder? { nil }
}

/// Test plugin that records every lifecycle callback.
@MainActor
class LifecyclePlugin: KirbyPlugin {
    class var label: String { "plugin" }
    private var recorder: CallRecorder?

    required init() {}

    private func record(_ method: String) { recorder?.add("\(Self.label).\(method)") }

    func didAttach(to context: KirbyContext) {
        recorder = context[CallRecorderKey.self]
        record("didAttach")
    }
    func willDetach(from context: KirbyContext) { record("willDetach") }
    func viewDidLoad() { record("viewDidLoad") }
    func viewWillAppear(_ animated: Bool) { record("viewWillAppear") }
    func viewIsAppearing(_ animated: Bool) { record("viewIsAppearing") }
    func viewDidAppear(_ animated: Bool) { record("viewDidAppear") }
    func viewWillDisappear(_ animated: Bool) { record("viewWillDisappear") }
    func viewDidDisappear(_ animated: Bool) { record("viewDidDisappear") }
    func viewWillLayoutSubviews() { record("viewWillLayoutSubviews") }
    func viewDidLayoutSubviews() { record("viewDidLayoutSubviews") }
    func traitsDidChange(_ previous: UITraitCollection) { record("traitsDidChange") }
    func mainRequestWillSend(_ request: KirbyRequest, isRetry: Bool) { record("mainRequestWillSend(retry: \(isRetry))") }
    func mainRequestDidReceive(_ response: KirbyResponse) { record("mainRequestDidReceive") }
    func mainRequestDidParse(_ response: KirbyResponse) { record("mainRequestDidParse") }
    func mainRequestDidFail(_ error: KirbyRequestError) { record("mainRequestDidFail(\(error))") }
}

final class DeferredLifecyclePlugin: LifecyclePlugin {
    override class var label: String { "deferred" }
}

/// A performer stub with a configurable outcome and delay.
struct StubPerformer: KirbyRequestPerforming {
    struct UnexpectedError: Error {}

    enum Outcome: Sendable {
        case success(KirbyResponse)
        case failure(KirbyRequestError)
        case unexpectedError
    }

    var outcome: Outcome = .success(KirbyResponse(data: Data("{}".utf8)))
    var delay: Duration = .zero

    func perform(_ request: KirbyRequest) async throws -> KirbyResponse {
        if delay > .zero {
            try await Task.sleep(for: delay)
        }
        switch outcome {
        case .success(let response): return response
        case .failure(let error): throw error
        case .unexpectedError: throw UnexpectedError()
        }
    }
}

@MainActor
enum TestWindow {
    /// Puts a view controller in a visible window to drive the real UIKit lifecycle.
    static func show(_ root: UIViewController) -> UIWindow {
        let frame = CGRect(x: 0, y: 0, width: 390, height: 844)
        let scene = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first
        let window = scene.map { UIWindow(windowScene: $0) } ?? UIWindow(frame: frame)
        window.frame = frame
        window.rootViewController = root
        window.makeKeyAndVisible()
        window.layoutIfNeeded()
        return window
    }

    /// Swaps in an empty root so the previous page goes through disappear.
    static func clear(_ window: UIWindow) {
        window.rootViewController = UIViewController()
        window.layoutIfNeeded()
    }
}

/// Polls until the condition holds or `timeout` passes. Returns whether it held.
@MainActor
func waitUntil(timeout: Duration = .seconds(3), _ condition: @MainActor () -> Bool) async -> Bool {
    let deadline = ContinuousClock.now + timeout
    while !condition() {
        guard ContinuousClock.now < deadline else { return false }
        try? await Task.sleep(for: .milliseconds(10))
    }
    return true
}
