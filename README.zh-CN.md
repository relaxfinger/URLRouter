# URLRouter

[🇺🇸 English](README.md) · [文档目录](docs/README.md) · [完整入门博客](https://zhangjipeng.com/post-urlrouter.html)

> 面向模块化 Apple 平台 App 的 SwiftUI 路由基础设施。
>
> iOS 17+ · macOS 14+ · tvOS 17+ · watchOS 10+ · Swift 6

URLRouter 给 App 提供一个统一、可预期的跳转入口。按钮、推送通知、
Universal Link 或另一个 Feature，都可以提交同一条 HTTPS URL；URLRouter
会校验 URL、交给拥有它的 Feature 解析，并按 URL 声明的方式更新 SwiftUI
导航。

当 App 页面变多后，调用方无需再知道另一个 Feature 的 View 类型、初始化
参数或导航容器；它只使用该 Feature 已文档化的 URL 契约。这正是它在真实
模块化项目中的价值。

## 按你的目标开始

| 你想做什么 | 从这里开始 |
| --- | --- |
| 从一个 SwiftUI 按钮打开页面 | [5 分钟快速开始](docs/getting-started.zh-CN.md#5-分钟快速开始) |
| 接入 Universal Link 和模块化 Feature Package | [接入指南](docs/getting-started.zh-CN.md) |
| 理解模块边界和 URL 契约 | [架构说明](docs/architecture.zh-CN.md) |
| 接入远程开关、并发协调、埋点或 CI | [生产治理](docs/production-governance.zh-CN.md) |
| 跟着从头实践一遍 | [技术博客](https://zhangjipeng.com/post-urlrouter.html) |

README 故意保持简短。链接文档会解释为什么这样设计、生产环境如何接入，并
提供中文内容；你不需要在第一天就引入所有高级能力。

## 安装

在 Xcode 选择 **File → Add Package Dependencies…**，添加：

```text
https://github.com/relaxfinger/URLRouter.git
```

将 `URLRouter` 添加到 App Target，以及每一个声明 `RouteModule` 的 Feature
Package。

```swift
dependencies: [
    .package(url: "https://github.com/relaxfinger/URLRouter.git", from: "2.5.7")
]
```

`URLRouterPolicyProvider` 是同一个 Package 的可选 product。只有 App 需要
“先读缓存、后台刷新”的远程路由策略时才引入它；通常 Feature Package 只依赖
`URLRouter`。

```swift
.product(name: "URLRouter", package: "URLRouter")
// 仅 App 壳层在需要远程策略时添加：
.product(name: "URLRouterPolicyProvider", package: "URLRouter")
```

## 5 分钟快速开始

### 1. 由 Feature 负责自己的路径和目标页面

```swift
import SwiftUI
import URLRouter

enum ArticleFeature {
    static let module = RouteModule(
        id: "articles",
        resolve: { link in
            guard case ["articles", let id] = link.pathComponents, !id.isEmpty else {
                return nil
            }
            return ModuleRoute(
                moduleID: "articles",
                routeID: "detail",
                parameters: ["id": id]
            )
        },
        destination: { route in
            guard route.routeID == "detail", let id = route.parameters["id"] else {
                return nil
            }
            return AnyView(ArticleDetailView(articleID: id))
        }
    )
}
```

`resolve` 返回 `nil` 的意思就是“这条 URL 不归我”。一个 Feature 可以拥有多条
URL；把它们的解析和目标页面创建放在一起。

### 2. 在场景根部只注册一次 Feature 模块

```swift
import SwiftUI
import URLRouter

@main
struct CompanyApp: App {
    @State private var router = ModuleRouter()

    private let registry = ModuleRouteRegistry(modules: [ArticleFeature.module])

    var body: some Scene {
        WindowGroup {
            RouterHost(router: router) {
                ContentView()
            } destination: { route in
                registry.destination(for: route)
            }
            .moduleLinkRouting(
                router: router,
                registry: registry,
                allowedHosts: ["example.com"]
            )
        }
    }
}
```

每个场景只安装一次 `RouterHost` 与 `moduleLinkRouting`。每个窗口使用一个
`ModuleRouter`，多窗口之间的导航状态就不会互相影响。

### 3. 用标准 SwiftUI API 跳转

```swift
struct ArticleRow: View {
    @Environment(\.openURL) private var openURL
    let articleID: String

    var body: some View {
        Button("阅读文章") {
            openURL(URL(string: "https://example.com/articles/\(articleID)?presentation=push&version=1")!)
        }
    }
}
```

URL 就是公开契约：

```text
https://example.com/articles/42?presentation=push&version=1
```

`presentation` 必填，可取 `push`、`tab`、`sheet` 或 `fullScreenCover`。
先跑通这一条路由，再阅读[接入指南](docs/getting-started.zh-CN.md)，安全地加入
URL builder、Universal Link、Tab 和带版本的路由协议。

## 什么时候再加可选的生产能力

不需要一次性全做完。

| 需求 | 加入什么 |
| --- | --- |
| 网页链接也要打开同一页面 | Universal Link |
| 要远程暂停某个 Feature 或全部路由 | `URLRouterPolicyProvider` 与 `ModuleRoutePolicyStore` |
| 推送、链接、按钮可能同时到达 | 每个场景一个 `ModuleRouteCoordinator` |
| 客服需要知道链接为什么没反应 | `ModuleRouteObservability` |
| 营销或网页依赖公开链接 | `RouteContracts.json` 与契约 CI |

这些能力都是按需接入。URLRouter 不会替你选网络客户端、登录流程、远程配置
厂商、埋点厂商或后端；这些仍是 App 的责任，Package 只提供清晰的路由边界。

## 路由契约与插件工作流

URLRouter 只维护一份位于 App 根目录的路由契约，而不是每个 Feature 各一份。它会扫描
Feature Package 和 App 自身的 Swift 源码，并生成两个需要审查、提交的产物：

- `RouteContracts.json`：公开 URL 契约，用于兼容性校验。
- `docs/route-catalog.html`：按 App 与 Feature Package 分组、可搜索的路由目录。

`URLRouterRouteBuildPlugin` 会在每次编译时校验契约，并在 Derived Data 生成临时网页目录。
开发者修改公开路由时，`URLRouterRouteCommandPlugin` 会明确更新受 Git 跟踪的
`RouteContracts.json` 和 `docs/route-catalog.html`。

完整的 Xcode 逐步配置（如何添加 Build Plugin、执行 Command Plugin、审查输出，以及插件
未出现在列表时如何排查）见[路由插件工作流](docs/route-plugin-workflow.zh-CN.md)。

## 示例 App

`URLRouterDemo` 是 iOS 17+ 的参考 App，演示本地 Feature Package、直接由 App 承载的路由、
四种展示方式、跨 Package 跳转、缓存优先策略生命周期、遥测和并发路由协调。

核心库和 `RouterHost` 支持上述四个平台。macOS 的 SwiftUI 没有
`fullScreenCover`，因此该展示方式会自动以 sheet 呈现。

## 项目结构

```text
Sources/URLRouter/                 # 核心路由库
Sources/URLRouterPolicyProvider/   # 可选策略刷新 product
Tests/                             # SwiftPM 单元测试
Features/                          # 本地 Feature Package 示例
URLRouterDemo/                     # 可运行的 iOS 参考 App
docs/                              # 按任务拆分的文档
```

## 许可证与社区

URLRouter 以 [MIT License](LICENSE) 发布。提交 PR 前请阅读
[CONTRIBUTING.md](CONTRIBUTING.md)。支持、漏洞报告和维护策略请见
[SUPPORT.md](SUPPORT.md)、[SECURITY.md](SECURITY.md) 与
[MAINTENANCE.md](MAINTENANCE.md)。
