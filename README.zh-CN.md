# KirbyiOS

[English](README.md) | 简体中文

UIKit 页面框架：页面级 context、命名事件、接收全部生命周期的 plugin、基类驱动的主接口、基于 Observation 的自动渲染。代码里 `import KirbyiOS`，类型统一用 `Kirby` 前缀。

## 环境要求

- iOS 18.4+，UIKit，Swift 6 语言模式，Xcode 26+
- 依赖：WildFunctionKit、Alamofire（默认的请求实现）

## 安装

```swift
.package(url: "https://github.com/WildFunction/KirbyiOS.git", from: "0.2.1")
// target 依赖：.product(name: "KirbyiOS", package: "KirbyiOS")
```

## 概念

| 类型 | 作用 |
| --- | --- |
| `KirbyViewController` / `KirbyCollectionViewController` | 页面基类 |
| `KirbyContext` | 页面级强类型存储（`context[Key.self]`），持有事件中心 |
| `KirbyEventCenter` | `context.event`：页面内的命名事件 |
| `KirbyPlugin` / `BaseKirbyPlugin` | 横切逻辑；接收视图和主接口的回调 |
| `KirbyViewModel` | `@Observable` 的页面状态 |
| `KirbyRequest` / `KirbyResponse` / `KirbyRequestError` | 主接口模型 |

## 用法

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

    // plugin：列出类即可，基类按顺序创建并挂载
    override func pluginClasses() -> [any KirbyPlugin.Type] { [LoadingStatePlugin.self] }

    // 主接口：viewDidLoad 结束时自动发起
    override func mainRequest() -> KirbyRequest? {
        KirbyRequest(url: "https://api.example.com/demo/detail", parameters: ["id": context[DemoIDKey.self]])
    }

    override func handleMainResponse(_ response: KirbyResponse) throws {
        guard let item = SafeJSON.decode(DemoItem.self, from: response.data) else { throw DemoError.invalidResponse }
        viewModel.apply(item)
    }

    override func mainRequestDidFail(_ error: KirbyRequestError) { /* 展示错误态；retryMainRequest() */ }

    override func setupUI() { /* 搭建视图 */ }
    override func setupEvents() { /* 订阅 context.event */ }

    // 这里读过的属性变化后自动重新执行
    override func render() { title = viewModel.title }
}

// plugin：按需重写任意生命周期方法
final class LoadingStatePlugin: BaseKirbyPlugin {
    private let indicator = UIActivityIndicatorView(style: .large)
    override func viewDidLoad() { context?.host?.view.addSubview(indicator) }
    override func mainRequestWillSend(_ request: KirbyRequest, isRetry: Bool) { indicator.startAnimating() }
    override func mainRequestDidParse(_ response: KirbyResponse) { indicator.stopAnimating() }
    override func mainRequestDidFail(_ error: KirbyRequestError) { indicator.stopAnimating() }
}

// 事件：一个名字加一个可选的数据
context.event.dispatch("itemSaved", "42")
context.event.subscribe("itemSaved", as: String.self) { [weak self] id in self?.refresh(id) }
observe("itemSaved", as: String.self) { [weak self] id in … }      // plugin 内使用，卸载时自动取消

// 子页面共用父页面的 context 和事件
let child = DemoChildViewController(context: context)
```

其他选项：

- `deferredPluginClasses()`：第一次 `viewDidAppear` 时才挂载的 plugin。
- `loadsMainRequestAutomatically`：返回 `false` 后自己调用 `loadMainRequest()`。
- `retryMainRequest()`、`cancelMainRequest()`、`isLoadingMainRequest`。
- `KirbyRequest(url:method: .post, parameters:)`：参数作为 JSON body（GET 为 query）。
- `KirbyRequestConfiguration.defaultPerformer`：设置一个 `KirbyRequestPerforming` 来接入自己的网络层。
- `setNeedsRender()`：依赖非 Observable 状态时手动触发渲染。

## 生命周期顺序

1. `init`：创建 context。
2. 首次 `loadView`：按 `pluginClasses()` 创建 plugin，调用 `didAttach`。
3. `viewDidLoad`：`setupUI()` → `setupEvents()` → plugin 的 `viewDidLoad` → 发起主接口。
4. appear / disappear / layout：先 `super`，再按列表顺序转发给 plugin。延后的 plugin 在第一次 `viewDidAppear` 挂载。
5. 主接口：`mainRequestWillSend` → `mainRequestDidReceive` → `handleMainResponse(_:)` → `mainRequestDidParse`；任一步失败 → `mainRequestDidFail`。被取消的请求不回调。
6. `render()`：首次布局前执行一次，之后在读过的状态变化时执行。
7. `deinit`：取消请求，按逆序对 plugin 调用 `willDetach`，清空事件。

## 约定

- 事件 handler 必须写 `[weak self]`，页面强持有自己的 handler。DEBUG 下页面被 pop 2 秒后仍存活会打 `possible retain cycle`。
- plugin 只有 `init()`，配置从 `context` 读取。不写业务逻辑、不持有 ViewModel、不引用其他 plugin，只通过 `context.event` 通信。
- ViewModel 不发请求，页面在 `handleMainResponse(_:)` 里把结果交给它。
- `render()` 只把状态赋给视图：幂等，不发请求，不派发事件。
- 事件不回放：只有派发时已订阅的 handler 会被调用。
- 主接口地址必须是 `http(s)`。

## 模板

```bash
Templates/install.sh                                   # Xcode：File > New > File from Template… > WildFunction Page
Templates/new-page.sh DemoDetail --output <dir>        # 命令行：生成 <dir>/DemoDetail/，含 4 个文件
Templates/new-page.sh DemoList --list --output <dir>   # KirbyCollectionViewController 版本
```

## 测试

```bash
KIRBYIOS_STRICT=1 xcodebuild test -scheme KirbyiOS -destination 'platform=iOS Simulator,name=iPhone 17'

# Example App（同时用到 WildFunctionKit 和 WFRouter），带 UI 测试
cd Example && xcodegen generate
xcodebuild test -project Example.xcodeproj -scheme Example -destination 'platform=iOS Simulator,name=iPhone 17'
```

## 相关

[WildFunctionKit](https://github.com/WildFunction/WildFunctionKit)（基础工具） · [WFRouter](https://github.com/WildFunction/WFRouter)（路由；在 `configure(with:info:)` 里把路由参数写进 context）

## 开源协议

MIT，见 [LICENSE](LICENSE)。
