import UIKit
import WildFunctionKit

/// Contract for page view models: main-actor isolated and observable.
///
/// ```swift
/// @MainActor @Observable
/// final class DemoDetailViewModel: KirbyViewModel {
///     var title = ""
///     var isLoading = false
/// }
/// ```
///
/// Properties read in `render()` trigger a new `render()` when they change.
@MainActor
public protocol KirbyViewModel: AnyObject, Observable {}

/// Interface of a Kirby page, implemented by ``KirbyViewController``.
@MainActor
public protocol KirbyHosting: UIViewController {
    /// The page's context.
    var context: KirbyContext { get }
    /// The page's plugin host.
    var pluginHost: KirbyPluginHost { get }
}

/// Internals of the base view controller.
@MainActor
enum KirbySupport {
    /// Traits observed by default: appearance, size classes and content size.
    static let defaultObservedTraits: [UITrait] = [
        UITraitUserInterfaceStyle.self,
        UITraitHorizontalSizeClass.self,
        UITraitVerticalSizeClass.self,
        UITraitPreferredContentSizeCategory.self,
    ]

    /// Whether `render()` is driven by `updateProperties()` (iOS 26+) rather than ``KirbyRenderTracker``.
    static var rendersInUpdateProperties: Bool {
        if #available(iOS 26, *) { true } else { false }
    }

    /// Teardown: detaches plugins and, when the page owns the context, clears its events to break cycles.
    static func tearDown(context: KirbyContext, pluginHost: KirbyPluginHost, clearsEvents: Bool) {
        pluginHost.detachAll()
        if clearsEvents {
            context.event.removeAll()
        }
    }
}

/// Schedules `render()` before iOS 26: once on first layout, then whenever state it read changes.
///
/// Uses `withObservationTracking` directly, because UIKit's own tracking on iOS 18 needs an Info.plist
/// flag and does not reliably re-run layout for `UICollectionViewController`.
@MainActor
final class KirbyRenderTracker {
    private(set) var needsRender = true

    /// Marks the next ``renderIfNeeded(_:onInvalidate:)`` as needed.
    func setNeedsRender() {
        needsRender = true
    }

    /// Runs `render` when needed, tracking what it reads and calling `onInvalidate` when that changes.
    func renderIfNeeded(_ render: () -> Void, onInvalidate: @escaping @MainActor @Sendable () -> Void) {
        guard needsRender else { return }
        needsRender = false
        withObservationTracking(render) { [weak self] in
            // onChange fires in willSet, so invalidate after the current mutation finishes.
            Task { @MainActor in
                self?.needsRender = true
                onInvalidate()
            }
        }
    }
}

/// DEBUG leak check: logs an error when a page is still alive a while after being popped or dismissed.
///
/// The usual cause is an event handler capturing the page strongly.
@MainActor
enum KirbyLeakDetector {
    static let defaultDelay: Duration = .seconds(2)

    /// Call when the page is leaving its navigation stack or being dismissed.
    static func scheduleCheckIfLeaving(_ viewController: UIViewController) {
        #if DEBUG
        guard viewController.isMovingFromParent || viewController.isBeingDismissed else { return }
        scheduleCheck(for: viewController, after: defaultDelay) { typeName in
            AppLog.error(
                "\(typeName) is still alive \(defaultDelay) after leaving the screen, possible retain cycle",
                category: .ui
            )
        }
        #endif
    }

    /// Checks after `delay` and calls `report` when the page is still alive and detached from the hierarchy.
    @discardableResult
    static func scheduleCheck(
        for viewController: UIViewController,
        after delay: Duration,
        report: @escaping @MainActor (String) -> Void
    ) -> Task<Void, Never> {
        let typeName = String(describing: type(of: viewController))
        return Task { @MainActor [weak viewController] in
            try? await Task.sleep(for: delay)
            guard let viewController, isDetached(viewController) else { return }
            report(typeName)
        }
    }

    private static func isDetached(_ viewController: UIViewController) -> Bool {
        viewController.parent == nil
            && viewController.presentingViewController == nil
            && viewController.viewIfLoaded?.window == nil
    }
}
