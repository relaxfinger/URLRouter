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
    .package(url: "https://github.com/relaxfinger/URLRouter.git", from: "2.5.3")
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

## Demo 与验证

`URLRouterDemo` 是 iOS 17+ 的参考 App，演示本地 Feature Package、四种展示
方式、跨 Package 跳转、缓存优先策略生命周期、遥测和并发路由协调。

```bash
swift test
swift Scripts/update_route_contracts.swift
swift Scripts/validate_route_contract.swift RouteContracts.json
swift Scripts/generate_route_catalog.swift
```

`update_route_contracts.swift` 会扫描当前 App 根目录内所有声明 `RouteModule` 的 Feature Swift
Package，以及 App 自身的 Swift 源码，并生成或更新根目录唯一的 `RouteContracts.json`。随后，
最后一条命令会扫描相同范围，并在
`docs/route-catalog.html` 生成可搜索的本地路由目录：URL 模板、路径/查询参数、目标页面、
Feature package 和展示方式都会列出。目录按 Feature package 分为独立表格，顶部提供带路由数
量的快速定位入口；App 自身的路由会显示在独立的 `App` 分区。

当脚本放在 URLRouter 包内、但要扫描另一个 App 时，指定 App 根目录即可（契约和输出路径
均相对于该根目录）：

```bash
swift /path/to/URLRouter/Scripts/generate_route_catalog.swift \
  --app-root /path/to/MyApp \
  --contracts RouteContracts.json \
  --output docs/route-catalog.html
```

同一个 App 根目录只能有一份 `RouteContracts.json`；Feature Package 不应各自维护副本。
生成器会识别标准的 `RouteModule` 解析器、`ModuleRoute` 与 URL builder 写法；无法可靠推导
路径或参数时会失败，而不会生成猜测的契约。

### 远程 SPM 依赖的自动执行

URLRouter 提供两个无需硬编码 checkout 路径的 Plugin Product。将远程 URLRouter 依赖添加到
App 后，在 target 的 **Build Phases → Run Build Tool Plug-ins** 中启用
`URLRouterRouteBuildPlugin`。每次编译会校验路由契约，并在 Derived Data 的插件工作目录生成
可浏览的路由网页；它不会改写 App 仓库。

新增或修改路由后，在 Xcode 选择 **File → Packages → URLRouterRouteCommandPlugin**，或在
Swift Package App 根目录运行：

```bash
swift package plugin generate-urlrouter-contracts --allow-writing-to-package-directory
```

该命令会明确请求写入授权，再更新 App 根目录的 `RouteContracts.json` 和
`docs/route-catalog.html`，供审查并提交 Git。

完整的 Xcode 逐步配置（如何添加 Build Plugin、执行 Command Plugin、审查输出，以及插件
未出现在列表时如何排查）见[路由插件工作流](docs/route-plugin-workflow.zh-CN.md)。

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
