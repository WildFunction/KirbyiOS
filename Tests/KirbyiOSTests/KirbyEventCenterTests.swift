import Testing
@testable import KirbyiOS
@testable import WildFunctionKit

private enum EventName {
    static let ping = "ping"
    static let other = "other"
}

@MainActor
private final class Log {
    var entries: [String] = []
    func add(_ entry: String) { entries.append(entry) }
}

private final class Captured {}

@MainActor
@Suite("KirbyEventCenter")
struct KirbyEventCenterTests {
    private let center = KirbyEventCenter()
    private let log = Log()

    // MARK: Dispatch

    @Test("Dispatch is synchronous")
    func dispatchIsSynchronous() {
        center.subscribe(EventName.ping) { [log] payload in log.add("got \(payload as? Int ?? -1)") }
        center.dispatch(EventName.ping, 7)
        #expect(log.entries == ["got 7"])
    }

    @Test("Handlers receive nil when no payload is given")
    func dispatchWithoutPayload() {
        center.subscribe(EventName.ping) { [log] payload in log.add(payload == nil ? "nil" : "value") }
        center.dispatch(EventName.ping)
        #expect(log.entries == ["nil"])
    }

    @Test("Only subscribers of the same name are called")
    func dispatchIsScopedByName() {
        center.subscribe(EventName.ping) { [log] _ in log.add("ping") }
        center.subscribe(EventName.other) { [log] _ in log.add("other") }
        center.dispatch(EventName.other)
        #expect(log.entries == ["other"])
    }

    @Test("Handlers run in subscription order")
    func runsInSubscriptionOrder() {
        for index in 1...4 {
            center.subscribe(EventName.ping) { [log] _ in log.add("h\(index)") }
        }
        center.dispatch(EventName.ping)
        #expect(log.entries == ["h1", "h2", "h3", "h4"])
    }

    @Test("Dispatching without subscribers is harmless")
    func dispatchWithoutSubscribers() {
        center.dispatch(EventName.ping)
        center.dispatch(EventName.ping, "x")
        #expect(log.entries.isEmpty)
    }

    // MARK: Typed subscriptions

    @Test("subscribe(as:) calls back only for a matching payload type")
    func typedSubscription() {
        center.subscribe(EventName.ping, as: String.self) { [log] text in log.add(text) }
        center.dispatch(EventName.ping, "hello")
        center.dispatch(EventName.ping, 42)
        center.dispatch(EventName.ping)
        #expect(log.entries == ["hello"])
    }

    // MARK: Snapshot

    @Test("Subscribing during dispatch does not affect the current round")
    func subscribingDuringDispatchDoesNotAffectCurrentRound() {
        center.subscribe(EventName.ping) { [center, log] _ in
            log.add("first")
            center.subscribe(EventName.ping) { _ in log.add("added") }
        }
        center.dispatch(EventName.ping)
        #expect(log.entries == ["first"])

        center.dispatch(EventName.ping)
        #expect(log.entries == ["first", "first", "added"])
    }

    @Test("Cancelling during dispatch takes effect on the next round")
    func cancellingDuringDispatchDoesNotAffectCurrentRound() {
        var second: KirbyEventSubscription?
        center.subscribe(EventName.ping) { [log] _ in
            log.add("first")
            second?.cancel()
        }
        second = center.subscribe(EventName.ping) { [log] _ in log.add("second") }

        center.dispatch(EventName.ping)
        #expect(log.entries == ["first", "second"])

        center.dispatch(EventName.ping)
        #expect(log.entries == ["first", "second", "first"])
    }

    // MARK: Reentrancy

    @Test("Reentrant dispatch runs inline")
    func reentrantDispatchRunsInline() {
        center.subscribe(EventName.ping) { [center, log] _ in
            log.add("ping-begin")
            center.dispatch(EventName.other)
            log.add("ping-end")
        }
        center.subscribe(EventName.other) { [log] _ in log.add("other") }
        center.subscribe(EventName.ping) { [log] _ in log.add("ping-second") }

        center.dispatch(EventName.ping)
        #expect(log.entries == ["ping-begin", "other", "ping-end", "ping-second"])
    }

    @Test("Recursion deeper than 16 levels is aborted")
    func recursionIsCapped() {
        var calls = 0
        center.subscribe(EventName.ping) { [center] _ in
            calls += 1
            center.dispatch(EventName.ping)
        }
        center.dispatch(EventName.ping)
        #expect(calls == KirbyEventCenter.maxRecursionDepth)
        #expect(KirbyEventCenter.maxRecursionDepth == 16)

        // The depth counter resets afterwards, so the center keeps working.
        calls = 0
        center.dispatch(EventName.ping)
        #expect(calls == 16)
    }

    // MARK: No replay

    @Test("Late subscribers do not receive past events")
    func lateSubscribersDoNotReceivePastEvents() {
        center.dispatch(EventName.ping, 1)
        center.subscribe(EventName.ping) { [log] _ in log.add("ping") }
        #expect(log.entries.isEmpty)

        center.dispatch(EventName.ping, 2)
        #expect(log.entries == ["ping"])
    }

    // MARK: Cancellation and cleanup

    @Test("cancel removes one subscription and is idempotent")
    func cancelSubscription() {
        let token = center.subscribe(EventName.ping) { [log] _ in log.add("a") }
        center.subscribe(EventName.ping) { [log] _ in log.add("b") }
        token.cancel()
        token.cancel()
        center.dispatch(EventName.ping)
        #expect(log.entries == ["b"])
    }

    @Test("Cancelling the last subscription leaves no subscribers")
    func cancelLastSubscription() {
        let token = center.subscribe(EventName.ping) { [log] _ in log.add("a") }
        token.cancel()
        center.dispatch(EventName.ping)
        #expect(log.entries.isEmpty)
    }

    @Test("cancel is safe after the center is deallocated")
    func cancelAfterCenterDeallocated() {
        var local: KirbyEventCenter? = KirbyEventCenter()
        let token = local?.subscribe(EventName.ping) { _ in }
        local = nil
        token?.cancel()
    }

    @Test("removeAll clears every subscription")
    func removeAll() {
        center.subscribe(EventName.ping) { [log] _ in log.add("ping") }
        center.subscribe(EventName.other) { [log] _ in log.add("other") }
        center.removeAll()

        center.dispatch(EventName.ping)
        center.dispatch(EventName.other)
        #expect(log.entries.isEmpty)
    }

    @Test("Deallocation releases objects captured by handlers")
    func releasesHandlers() {
        weak var weakCaptured: Captured?
        do {
            let local = KirbyEventCenter()
            let captured = Captured()
            weakCaptured = captured
            local.subscribe(EventName.ping) { _ in _ = captured }
        }
        #expect(weakCaptured == nil)
    }
}
