import UIKit
import WildFunctionKit

/// A strongly typed key for ``KirbyContext``, modeled after SwiftUI's `EnvironmentKey`.
///
/// ```swift
/// enum DemoIDKey: KirbyContextKey { static let defaultValue = "" }
///
/// context[DemoIDKey.self] = "12345"
/// let id = context[DemoIDKey.self]
/// ```
public protocol KirbyContextKey {
    /// The value type stored under this key.
    associatedtype Value
    /// The value returned before anything is written.
    static var defaultValue: Value { get }
}

/// Per-page context: strongly typed shared data plus a page-scoped event center.
///
/// Each page owns its own context; nothing is shared globally.
@MainActor
public final class KirbyContext {
    /// The page's event center. Events never leave the page.
    public let event: KirbyEventCenter

    /// The hosting view controller. Held weakly.
    public weak var host: UIViewController?

    private var storage: [ObjectIdentifier: Any] = [:]

    /// Creates an empty context.
    public init() {
        event = KirbyEventCenter()
    }

    /// Reads or writes the value for a key. Unwritten keys return their default value.
    public subscript<K: KirbyContextKey>(_ key: K.Type) -> K.Value {
        get {
            storage[ObjectIdentifier(key)] as? K.Value ?? K.defaultValue
        }
        set {
            storage[ObjectIdentifier(key)] = newValue
        }
    }

    /// Whether a value was explicitly written for the key.
    public func contains<K: KirbyContextKey>(_ key: K.Type) -> Bool {
        storage[ObjectIdentifier(key)] != nil
    }

    /// Removes the value for a key, restoring its default.
    public func remove<K: KirbyContextKey>(_ key: K.Type) {
        storage[ObjectIdentifier(key)] = nil
    }

    /// Function form of the subscript getter.
    public func value<K: KirbyContextKey>(_ key: K.Type) -> K.Value {
        self[key]
    }

    /// Function form of the subscript setter.
    public func set<K: KirbyContextKey>(_ key: K.Type, _ value: K.Value) {
        self[key] = value
    }
}
