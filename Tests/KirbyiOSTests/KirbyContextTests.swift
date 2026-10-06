import Testing
import UIKit
@testable import KirbyiOS
@testable import WildFunctionKit

private enum DemoIDKey: KirbyContextKey { static let defaultValue = "" }
private enum ShowsBadgeKey: KirbyContextKey { static let defaultValue = false }
private enum CountKey: KirbyContextKey { static let defaultValue = 3 }
private enum OptionalNameKey: KirbyContextKey { static let defaultValue: String? = nil }

@MainActor
@Suite("KirbyContext")
struct KirbyContextTests {
    @Test("Returns the default value before any write")
    func returnsDefaultValue() {
        let context = KirbyContext()
        #expect(context[DemoIDKey.self] == "")
        #expect(context[ShowsBadgeKey.self] == false)
        #expect(context[CountKey.self] == 3)
        #expect(context[OptionalNameKey.self] == nil)
    }

    @Test("Stores values independently per key")
    func storesValuesPerKey() {
        let context = KirbyContext()
        context[DemoIDKey.self] = "12345"
        context[ShowsBadgeKey.self] = true
        context[CountKey.self] += 1

        #expect(context[DemoIDKey.self] == "12345")
        #expect(context[ShowsBadgeKey.self])
        #expect(context[CountKey.self] == 4)
    }

    @Test("contains reflects explicit writes only")
    func containsReflectsExplicitWrites() {
        let context = KirbyContext()
        #expect(!context.contains(DemoIDKey.self))
        context[DemoIDKey.self] = ""
        #expect(context.contains(DemoIDKey.self))
    }

    @Test("remove restores the default value")
    func removeRestoresDefault() {
        let context = KirbyContext()
        context[CountKey.self] = 10
        context.remove(CountKey.self)
        #expect(context[CountKey.self] == 3)
        #expect(!context.contains(CountKey.self))
        context.remove(CountKey.self)
    }

    @Test("value / set convenience accessors")
    func convenienceAccessors() {
        let context = KirbyContext()
        context.set(DemoIDKey.self, "abc")
        #expect(context.value(DemoIDKey.self) == "abc")
        context.set(OptionalNameKey.self, "name")
        #expect(context.value(OptionalNameKey.self) == "name")
    }

    @Test("Contexts are isolated from each other")
    func contextsAreIsolated() {
        let first = KirbyContext()
        let second = KirbyContext()
        first[DemoIDKey.self] = "1"
        #expect(second[DemoIDKey.self] == "")
        #expect(first.event !== second.event)
    }

    @Test("host is held weakly")
    func hostIsWeak() {
        let context = KirbyContext()
        do {
            let viewController = UIViewController()
            context.host = viewController
            #expect(context.host === viewController)
        }
        #expect(context.host == nil)
    }

    @Test("Deallocation releases stored objects")
    func releasesStoredObjects() {
        final class Payload {}
        enum PayloadKey: KirbyContextKey { static var defaultValue: Payload? { nil } }

        weak var weakContext: KirbyContext?
        weak var weakPayload: Payload?
        weak var weakCenter: KirbyEventCenter?
        do {
            let context = KirbyContext()
            let payload = Payload()
            context[PayloadKey.self] = payload
            context.event.subscribe("ping") { _ in }
            weakContext = context
            weakPayload = payload
            weakCenter = context.event
        }
        #expect(weakContext == nil)
        #expect(weakPayload == nil)
        #expect(weakCenter == nil)
    }
}
