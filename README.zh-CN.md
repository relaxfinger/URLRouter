# URLRouter

[🇺🇸 English](README.md)

> iOS 17+ · macOS 14+ · tvOS 17+ · watchOS 10+ · Swift 6 · SwiftUI · 模块化 `openURL` 路由

URLRouter 是面向模块化 App 的 SwiftUI 路由基础库。Feature 页面统一使用 `openURL` 跳转；URLRouter 负责校验 URL、找到所属 Feature Package，并执行 URL 中声明的展示方式。

## 目录

1. [安装](#安装)
2. [架构](#架构)
3. [配置 Universal Link](#配置-universal-link)
4. [Feature Package](#feature-package)
5. [App Shell](#app-shell)
6. [生产治理](#生产治理)
7. [常见路由场景](#常见路由场景)
8. [Demo 与测试](#demo-与测试)

## 安装

在 Xcode 的 **File > Add Package Dependencies…** 添加 `https://github.com/relaxfinger/URLRouter.git`，随后导入 `URLRouter`。最低支持 iOS 17、macOS 14、tvOS 17 或 watchOS 10。

### 兼容性

- Apple 2023 年同代系统：iOS 17+、macOS 14+、tvOS 17+ 与 watchOS 10+
- Swift 6 语言模式
- Xcode 16 或更高版本

### 包结构

仓库遵循 Swift Package Manager 的标准目录约定。库与测试可直接由 SwiftPM 构建；Xcode 工程仅作为可运行的 Demo 宿主。

```text
Sources/URLRouter/        # 公共库源码
Sources/URLRouterPolicyProvider/ # 可选的缓存优先策略刷新模块
Tests/URLRouterTests/     # 单元测试
Tests/URLRouterPolicyProviderTests/ # Provider 单元测试
Features/                 # 本地 Feature Package 示例
URLRouterDemo/            # SwiftUI Demo 应用
```

## 架构

URLRouter 让 Feature 页面统一通过 `openURL` 跳转。App Shell 一次性注册各 Feature Package 后，使用完整 HTTPS URL 并携带必填 `presentation` query 即可。合法值为 `push`、`tab`、`sheet`、`fullScreenCover`。生产环境的 App Shell 还可通过 `ModuleRoutePolicy` 强制执行版本化 URL 协议，通过 `ModuleRoutePolicyStore` 接入远程限制，并通过 `ModuleRouteObservability` 输出供应商无关的遥测事件。

```text
https://example.com/articles/42?presentation=push&version=1
https://example.com/favorites?presentation=tab&version=1
https://example.com/settings?presentation=sheet&version=1
https://example.com/sign-in?presentation=fullScreenCover&version=1
```


## 配置 Universal Link

1. 在 target 添加 **Associated Domains** capability，并添加 `applinks:example.com`。
2. 通过 HTTPS 且不重定向地部署 `https://example.com/.well-known/apple-app-site-association`。
3. 只在 `WindowGroup` 根部安装一次 `moduleLinkRouting`。

AASA 示例（替换团队 ID 与 bundle ID）：

```json
{
  "applinks": {
    "details": [{
      "appIDs": ["TEAM_ID.com.example.MyApp"],
      "components": [{ "/": "/articles/*" }, { "/": "/settings" }]
    }]
  }
}
```

## Feature Package

每个 Feature Package 注册自己的 URL 语法与目标 View；只有这一层知道自己的路径和页面。

```swift
import SwiftUI
import URLRouter

enum ArticleFeature {
    static let id = "articles"

    static let module = RouteModule(
        id: id,
        resolve: { link in
            switch link.pathComponents {
            case ["articles", let articleID]:
                return ModuleRoute(
                    moduleID: id,
                    routeID: "detail",
                    parameters: ["id": articleID]
                )
            case ["articles", let articleID, "comments"]:
                return ModuleRoute(
                    moduleID: id,
                    routeID: "comments",
                    parameters: ["id": articleID]
                )
            case ["articles", "search"]:
                return ModuleRoute(moduleID: id, routeID: "search")
            default:
                return nil
            }
        },
        destination: { route in
            switch route.routeID {
            case "detail":
                return AnyView(ArticleView(id: route.parameters["id"] ?? ""))
            case "comments":
                return AnyView(CommentsView(articleID: route.parameters["id"] ?? ""))
            case "search":
                return AnyView(ArticleSearchView())
            default:
                return nil
            }
        }
    )
}
```

普通 Feature 页面只需要 SwiftUI：

```swift
struct ArticleList: View {
    @Environment(\.openURL) private var openURL

    var body: some View {
        Button("打开文章 42") {
            openURL(URL(string: "https://example.com/articles/42?presentation=push&version=1")!)
        }
    }
}
```

因此，一个 `RouteModule` 可以负责多个 link。以上 Feature 对外声明了以下 URL 协议：

```text
https://example.com/articles/42?presentation=push&version=1
https://example.com/articles/42/comments?presentation=sheet&version=1
https://example.com/articles/search?presentation=tab&version=1
```

路径决定 `routeID` 和参数；`presentation` 决定 SwiftUI 如何展示已解析的页面。

## App Shell

App 只链接 Feature Package 并一次性注册模块；它不解析 Feature 路径，也不选择 push/tab/sheet/全屏展示方式。

```swift
@main
struct MyApp: App {
    @State private var router = ModuleRouter()
    private let routePolicy = ModuleRoutePolicy(
        acceptedContractVersions: ["1"],
        allowsUnversionedLinks: false
    )
    private let registry = ModuleRouteRegistry(modules: [
        ArticleFeature.module,
        SettingsFeature.module
    ])

    var body: some Scene {
        WindowGroup {
            RouterHost(router: router) {
                AppTabs(router: router)
            } destination: { route in
                registry.destination(for: route)
            }
            .moduleLinkRouting(
                router: router,
                registry: registry,
                allowedHosts: ["example.com"],
                policy: routePolicy,
                onFailure: { url, error in
                    print("Discarded route \(url.absoluteString): \(error.localizedDescription)")
                },
                onEvent: { event in
                    print("Route trace \(event.traceID): \(event.outcome.rawValue)")
                }
            )
        }
    }
}
```

Swift 无法在运行时发现未链接的 Package。存在两个或更多 Feature Package 时，App Shell 只需将每个 Package 唯一的 `RouteModule` 放入同一个注册表。新增 Feature 时仍要链接其 Package 并注册该模块，但永远不需要改中心化 URL `switch`、路径解析或展示方式映射。

注册表会拒绝重复 module ID、由错误模块返回的 route，以及没有 destination 的 push/sheet/full-screen route。`ModuleRoutePolicy` 让 App Shell 在不耦合 Feature Package 的前提下执行协议版本、Feature 开关、权限和允许的展示方式。使用 `onFailure` 记录被拒绝的 URL，使用 `onEvent` 接入隐私友好的遥测：事件包含 trace ID、处理结果和 route 元数据，不包含 query value。Router 同一时刻只保留一个模态 route：新的模态 route 会替换旧的；push 和 tab route 会先关闭当前模态展示再导航；重复 push 相同 route 是幂等的。

## 生产治理

### 远程策略与紧急熔断

`ModuleRouteRemotePolicy` 是可 `Codable` 解码的限制文档，App Shell 可从任意已批准的远程配置服务获取。库本身不访问网络：宿主 App 必须负责鉴权、验签、缓存和回滚。远程策略只能收紧本地策略，不能越过本地授权。

需要“先读缓存、后台刷新”的 App 生命周期时，可从同一个 Package 按需引入：

```swift
.product(name: "URLRouterPolicyProvider", package: "URLRouter")
```

`URLRouterPolicyProvider` 依赖 `URLRouter`，反过来核心库不依赖它。它不绑定 HTTP 客户端、远程配置厂商或签名方案；App 只实现这些小适配层，Provider 负责缓存优先启动、TTL、旧缓存回退和策略原子替换。

```swift
@State private var routePolicyStore = ModuleRoutePolicyStore(
    localPolicy: ModuleRoutePolicy(
        acceptedContractVersions: ["1"],
        allowsUnversionedLinks: false
    )
)

func applyTrustedRemotePolicy(_ data: Data) throws {
    let remotePolicy = try JSONDecoder().decode(ModuleRouteRemotePolicy.self, from: data)
    routePolicyStore.replaceRemotePolicy(with: remotePolicy)
}
```

将 `isCircuitBreakerOpen` 设为 `true`，即可不发版立即停止模块路由。该文档还可禁用指定模块、提供允许列表、拒绝某些展示方式或进一步收紧支持的协议版本。

### 推荐的 App 拉取策略

建议顺序是：启动先读取上一次已验证缓存，再在后台刷新；App 回到前台且超过 TTL 时按需刷新；短暂断网时继续使用最后一次可信策略。没有可信缓存，或缓存超过硬过期时间时，URLRouter 保持 App 内置的安全本地策略。

```swift
import URLRouter
import URLRouterPolicyProvider

struct CompanyPolicySource: RoutePolicyRemoteSource {
    func fetchPolicyData() async throws -> Data {
        let url = URL(string: "https://config.example.com/mobile/route-policy")!
        let (data, response) = try await URLSession.shared.data(from: url)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else {
            throw URLError(.badServerResponse)
        }
        return data
    }
}

@MainActor
final class AppRoutePolicySession {
    let store = ModuleRoutePolicyStore(localPolicy: ModuleRoutePolicy(
        acceptedContractVersions: ["1"],
        allowsUnversionedLinks: false
    ))
    let provider: RoutePolicyProvider

    init(cacheURL: URL) {
        provider = RoutePolicyProvider(
            store: store,
            source: CompanyPolicySource(),
            cache: FileRoutePolicyCache(url: cacheURL),
            strategy: .standard // 30 分钟刷新，1 小时常规缓存，24 小时硬过期
        )
    }

    func start() async {
        _ = await provider.bootstrap() // 先使用可信磁盘缓存；不等待网络
        _ = await provider.refresh()   // 在后台请求最新策略
    }

    func appBecameActive() async {
        _ = await provider.refreshIfNeeded()
    }
}
```

普通可信 JSON 接口可使用 `JSONRoutePolicyPayloadValidator`。如果响应有签名或信封结构，App 实现 `RoutePolicyPayloadValidating`；只有校验通过的 `ModuleRouteRemotePolicy` 才会写入缓存和生效。普通策略建议前台 30 分钟刷新、常规缓存 1 小时、硬过期 24 小时；对事故熔断，可按实际要求使用更短刷新间隔或静默推送触发刷新。

### 统一可观测性

为日志、指标、Tracing SDK 编写 `ModuleRouteObserving` 适配器，再将 `ModuleRouteObservability` 传给 `moduleLinkRouting`。每个事件包含 trace ID、结果、host、模块/路由标识、展示方式和稳定的 `failureCode`；它刻意不包含 URL query 值。

### 路由契约 CI

[`RouteContracts.json`](RouteContracts.json) 是受版本控制的公开路由目录。CI 会在构建前运行 `Scripts/validate_route_contract.swift`，拒绝重复的路由 ID 或路径/展示方式组合、非法展示方式，以及缺少 `presentation` 或 `version` 参数的契约。变更公开路由时，应同步更新目录、Feature 解析器、发布说明和迁移方案。

## 常见路由场景

| 业务意图 | Feature 代码 |
| --- | --- |
| Push 详情 | `openURL(URL(string: "https://example.com/articles/42?presentation=push&version=1")!)` |
| 切换 Tab | `openURL(URL(string: "https://example.com/favorites?presentation=tab&version=1")!)` |
| 展示 Sheet | `openURL(URL(string: "https://example.com/settings?presentation=sheet&version=1")!)` |
| 全屏流程 | `openURL(URL(string: "https://example.com/sign-in?presentation=fullScreenCover&version=1")!)` |

异步操作完成后，回到主线程再调用 `openURL`：

```swift
Task {
    let id = try await articleService.recommendedArticleID()
    await MainActor.run {
        openURL(URL(string: "https://example.com/articles/\(id)?presentation=push&version=1")!)
    }
}
```

### 从一个 Feature Package 跳转到另一个

Feature A 不导入 Feature B，也不引用 B 的 View；它只发送 B 已公开的 URL 协议：

```swift
// 位于 NavigationFeature
@Environment(\.openURL) private var openURL

Button("打开内容文章") {
    openURL(URL(string: "https://example.com/articles/42?presentation=push&version=1")!)
}
```

`ContentFeature` 负责 `/articles/*` 并提供 `ArticleView`。它也可以用相同方式跳回 `NavigationFeature`：

```swift
// 位于 ContentFeature
Button("打开设置") {
    openURL(URL(string: "https://example.com/settings?presentation=sheet&version=1")!)
}
```

两个模块都必须被链接并加入 `ModuleRouteRegistry`。Demo 注册了 `DemoNavigationFeature` 和 `DemoContentFeature`，并演示双向跳转。

## Demo 与测试

Demo 使用两个真实的本地 Swift Package：

```text
Features/
├── NavigationFeature/  # 首页、收藏、设置、登录
└── ContentFeature/     # 文章详情
```

两个 Package 都依赖 `URLRouter`，但它们互不依赖。`NavigationFeature` 打开由 `ContentFeature` 负责的文章 URL；`ContentFeature` 打开由 `NavigationFeature` 负责的设置 URL。

这是刻意设计的边界：跨 Feature 跳转应使用 URL 协议，不应为了访问对方 View 或路由类型而直接导入另一个 Feature Package。

`URLRouterDemo` 是 iOS 17+ 的参考应用，演示了跨平台的 `RouterHost` 组合方式、四种 URL 展示方式、跨 Package 跳转、严格的 version=1 协议校验、应用内路由遥测状态，以及可选 `URLRouterPolicyProvider` 的缓存优先刷新流程。Demo 的 `DemoPolicySource` 故意使用本地数据；生产环境请替换为 App 自己的来源。面向 macOS 14+、tvOS 17+ 或 watchOS 10+ 的 App 同样可使用 `RouterHost`、`moduleLinkRouting` 与 Feature Package；SwiftUI 会按平台适配导航和模态展示。由于 SwiftUI 在 macOS 上不提供 `fullScreenCover`，该展示方式会在 macOS 中以 sheet 呈现。

打开 `URLRouter.xcodeproj`，选择 **URLRouterDemo** scheme 与 iOS 17+ simulator 后运行，Xcode 会自动解析两个本地 Package。

运行测试：

```bash
swift test
swift Scripts/validate_route_contract.swift RouteContracts.json
```

## 许可证

URLRouter 使用 [MIT License](LICENSE) 发布。
