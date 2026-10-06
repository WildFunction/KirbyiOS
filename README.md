# KirbyiOS

English | [简体中文](README.zh-CN.md)

UIKit page framework: per-page context, named events, plugins that receive every lifecycle callback, a base-class driven main request, and Observation-driven rendering. Import `KirbyiOS`; types are prefixed `Kirby`.

## Requirements

- iOS 18.4+, UIKit, Swift 6 language mode, Xcode 26+
- Dependencies: WildFunctionKit, Alamofire (default request performer)

## Install

```swift
.package(url: "https://github.com/WildFunction/KirbyiOS.git", from: "0.2.0")
// target dependency: .product(name: "KirbyiOS", package: "KirbyiOS")
```

## Concepts

| Type | Role |
| --- | --- |
| `KirbyViewController` / `KirbyCollectionViewController` | Page base classes |
| `KirbyContext` | Typed per-page storage (`context[Key.self]`), owns the event center |
| `KirbyEventCenter` | `context.event`: named events inside one page |
| `KirbyPlugin` / `BaseKirbyPlugin` | Cross-cutting behavior; receives view and main-request callbacks |
| `KirbyViewModel` | `@Observable` page state |
| `KirbyRequest` / `KirbyResponse` / `KirbyRequestError` | Main request model |

## Usage

```swift
import KirbyiOS
import WildFunctionKit

enum DemoIDKey: KirbyContextKey { static let defaultValue = "" }

@MainActor @Observable
final class DemoDetailViewModel: KirbyViewModel {
    private(set) var title = ""
    func apply(_ item: DemoItem) { title = item.name }
}

final class DemoDetailViewController: KirbyViewController {
    let viewModel = DemoDetailViewModel()

    // Plugins: list classes; the base class creates and attaches them in order
    override func pluginClasses() -> [any KirbyPlugin.Type] { [LoadingStatePlugin.self] }

    // Main request: sent automatically at the end of viewDidLoad
    override func mainRequest() -> KirbyRequest? {
        KirbyRequest(url: "https://api.example.com/demo/detail", parameters: ["id": context[DemoIDKey.self]])
    }

    override func handleMainResponse(_ response: KirbyResponse) throws {
        guard let item = SafeJSON.decode(DemoItem.self, from: response.data) else { throw DemoError.invalidResponse }
        viewModel.apply(item)
    }

    override func mainRequestDidFail(_ error: KirbyRequestError) { /* show error; retryMainRequest() */ }

    override func setupUI() { /* build views */ }
    override func setupEvents() { /* subscribe to context.event */ }

    // Re-run automatically when a property read here changes
    override func render() { title = viewModel.title }
}

// Plugin: override any lifecycle method
final class LoadingStatePlugin: BaseKirbyPlugin {
    private let indicator = UIActivityIndicatorView(style: .large)
    override func viewDidLoad() { context?.host?.view.addSubview(indicator) }
    override func mainRequestWillSend(_ request: KirbyRequest, isRetry: Bool) { indicator.startAnimating() }
    override func mainRequestDidParse(_ response: KirbyResponse) { indicator.stopAnimating() }
    override func mainRequestDidFail(_ error: KirbyRequestError) { indicator.stopAnimating() }
}

// Events: a name plus an optional payload
context.event.dispatch("itemSaved", "42")
context.event.subscribe("itemSaved", as: String.self) { [weak self] id in self?.refresh(id) }
observe("itemSaved", as: String.self) { [weak self] id in … }      // inside a plugin; cancelled on detach

// Child page sharing the parent's context and events
let child = DemoChildViewController(context: context)
```

More options:

- `deferredPluginClasses()`: plugins attached on the first `viewDidAppear`.
- `loadsMainRequestAutomatically`: return `false`, then call `loadMainRequest()` yourself.
- `retryMainRequest()`, `cancelMainRequest()`, `isLoadingMainRequest`.
- `KirbyRequest(url:method: .post, parameters:)`: parameters become a JSON body (GET: query).
- `KirbyRequestConfiguration.defaultPerformer`: set a `KirbyRequestPerforming` to use your own networking.
- `setNeedsRender()`: re-render for non-observable state.

## Lifecycle order

1. `init`: context created.
2. First `loadView`: plugins from `pluginClasses()` created, `didAttach`.
3. `viewDidLoad`: `setupUI()` → `setupEvents()` → plugins' `viewDidLoad` → main request starts.
4. Appear / disappear / layout: `super`, then plugins in list order. Deferred plugins attach on first `viewDidAppear`.
5. Main request: `mainRequestWillSend` → `mainRequestDidReceive` → `handleMainResponse(_:)` → `mainRequestDidParse`; any failure → `mainRequestDidFail`. Cancelled requests call nothing.
6. `render()`: before first layout, then whenever observed state changes.
7. `deinit`: request cancelled, plugins `willDetach` in reverse order, events cleared.

## Rules

- Event handlers must capture `[weak self]`; the page retains its handlers. DEBUG logs `possible retain cycle` when a popped page is still alive after 2 s.
- Plugins have only `init()`; read configuration from `context`. No business logic, no view model, no references to other plugins; communicate through `context.event`.
- View models do not send requests; the page hands results over in `handleMainResponse(_:)`.
- `render()` only assigns state to views: idempotent, no requests, no event dispatch.
- Events are not replayed: only handlers subscribed at dispatch time are called.
- Main request URLs must be `http(s)`.

## Templates

```bash
Templates/install.sh                                   # Xcode: File > New > File from Template… > WildFunction Page
Templates/new-page.sh DemoDetail --output <dir>        # CLI: creates <dir>/DemoDetail/ with 4 files
Templates/new-page.sh DemoList --list --output <dir>   # KirbyCollectionViewController variant
```

## Test

```bash
xcodebuild test -scheme KirbyiOS -destination 'platform=iOS Simulator,name=iPhone 17'

# Example app (also exercises WildFunctionKit and WFRouter) with UI tests
cd Example && xcodegen generate
xcodebuild test -project Example.xcodeproj -scheme Example -destination 'platform=iOS Simulator,name=iPhone 17'
```

## Related

[WildFunctionKit](https://github.com/WildFunction/WildFunctionKit) (base utilities) · [WFRouter](https://github.com/WildFunction/WFRouter) (routing; write route parameters into the context in `configure(with:info:)`)

## License

MIT. See [LICENSE](LICENSE).
