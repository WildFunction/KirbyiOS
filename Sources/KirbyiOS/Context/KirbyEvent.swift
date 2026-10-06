import Foundation
import WildFunctionKit

/// A subscription token that can cancel the subscription.
///
/// It does not need to be retained; subscriptions live as long as their ``KirbyEventCenter``.
@MainActor
public final class KirbyEventSubscription {
    private var onCancel: (@MainActor () -> Void)?

    init(onCancel: @escaping @MainActor () -> Void) {
        self.onCancel = onCancel
    }

    /// Cancels the subscription. Safe to call more than once.
    public func cancel() {
        onCancel?()
        onCancel = nil
    }
}
