# URLRouter 接入指南

[English](getting-started.md) · [文档目录](README.zh-CN.md)

本指南先让你跑通一条接近生产形态的路由，再考虑远程配置和队列。目标很简单：
一个按钮和一条 Universal Link，都通过同一条公开 URL 打开同一个 SwiftUI 页面。

## 开始前

- 部署目标为 iOS 17+、macOS 14+、tvOS 17+ 或 watchOS 10+。
- 选择团队控制的 HTTPS 域名；下文用 `example.com` 举例。
- 为 App Target，以及每个声明 `RouteModule` 的 Feature Package 添加
  `URLRouter`。

暂时不要添加 `URLRouterPolicyProvider`。它是可选能力，只有需要远程管理路由
限制时才放到 App 壳层。

## 1. 定义一条稳定的 URL 契约

从一条完整 URL 开始，而不是从某个内部 View 名称开始：

```text
https://example.com/articles/42?presentation=push&version=1
```

- `/articles/42` 是目标页面。
- `presentation=push` 告诉 SwiftUI 如何展示。
- `version=1` 让未来的 App 可以支持新 URL 形状，而不是靠猜。

只使用 HTTPS 和可信 host。URL 中放稳定 ID，不放 token、密码、手机号或整段
JSON。一旦链接被放进网页、邮件或推送，它就是公开 API。

在拥有该路由的 Feature 中用 `URLComponents` 构造 URL，而不是在全 App 复制
字符串：

```swift
import Foundation

enum ArticleLinks {
    static func detail(id: String) -> URL {
        var components = URLComponents()
        components.scheme = "https"
        components.host = "example.com"
        components.path = "/articles/\(id)"
        components.queryItems = [
            URLQueryItem(name: "presentation", value: "push"),
            URLQueryItem(name: "version", value: "1")
        ]
        return components.url!
    }
}
```

## 2. 由拥有它的 Feature 解析 URL

Feature 同时拥有自己的 URL 语法和目标页面。解析器返回 `nil` 的意思是“这条
URL 属于另一个 Feature”。

```swift
import SwiftUI
import URLRouter

enum ArticleFeature {
    static let module = RouteModule(
        id: "articles",
        resolve: { link in
            switch link.pathComponents {
            case ["articles"]:
                return ModuleRoute(moduleID: "articles", routeID: "list")
            case ["articles", "saved"]:
                return ModuleRoute(moduleID: "articles", routeID: "saved")
            case ["articles", let id] where !id.isEmpty:
                return ModuleRoute(
                    moduleID: "articles",
                    routeID: "detail",
                    parameters: ["id": id]
                )
            default:
                return nil
            }
        },
        destination: { route in
            switch route.routeID {
            case "list":
                return AnyView(ArticleListView())
            case "saved":
                return AnyView(SavedArticlesView())
            case "detail":
                guard let id = route.parameters["id"] else { return nil }
                return AnyView(ArticleDetailView(articleID: id))
            default:
                return nil
            }
        }
    )
}
```

固定路径，例如 `/articles/saved`，要写在通用的 `/articles/:id` 前面；否则
`saved` 会被错误当成文章 ID。

## 3. 在 App 壳层组装模块

App 壳层是唯一知道当前链接了哪些 Feature Package 的地方。它注册模块、创建
导航状态、执行 App 级规则；但不解析 Feature 路径，也不创建 Feature 页面。

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
                AppTabs(router: router)
            } destination: { route in
                registry.destination(for: route)
            }
            .moduleLinkRouting(
                router: router,
                registry: registry,
                allowedHosts: ["example.com"],
                policy: ModuleRoutePolicy(
                    acceptedContractVersions: ["1"],
                    allowsUnversionedLinks: false
                )
            )
        }
    }
}
```

每个场景只安装一次 `RouterHost` 和 `moduleLinkRouting`。每个窗口有自己的
`ModuleRouter`，多窗口状态就不会互相影响。

## 4. 在普通 SwiftUI 代码中跳转

`moduleLinkRouting` 提供 SwiftUI 标准的 `openURL` action。子 View 不需要拿到
router：

```swift
struct ArticleRow: View {
    let id: String
    @Environment(\.openURL) private var openURL

    var body: some View {
        Button("阅读") {
            openURL(ArticleLinks.detail(id: id))
        }
    }
}
```

异步工作结束后，回到主线程再调用：

```swift
Task {
    let id = try await recommendationService.nextArticleID()
    await MainActor.run {
        openURL(ArticleLinks.detail(id: id))
    }
}
```

## 5. 让 tab 路由真的切换 TabView

收到 `presentation=tab` 时，URLRouter 更新 `router.selectedTab`。将
`TabView` 的 selection 绑定到它；tab 的 `routeID` 和 SwiftUI tag 要保持一致，
例如 `favorites`。

```swift
struct AppTabs: View {
    @Bindable var router: ModuleRouter

    var body: some View {
        TabView(selection: Binding(
            get: { router.selectedTab?.routeID ?? "home" },
            set: { router.selectedTab = ModuleRoute(moduleID: "navigation", routeID: $0) }
        )) {
            HomeView().tabItem { Label("首页", systemImage: "house") }.tag("home")
            FavoritesView().tabItem { Label("收藏", systemImage: "star") }.tag("favorites")
        }
    }
}
```

## 6. 接入 Universal Link

1. 为 App Target 添加 **Associated Domains** capability。
2. 添加 `applinks:example.com`。
3. 在 `https://example.com/.well-known/apple-app-site-association` 提供文件，
   必须 HTTPS 且不能重定向。
4. 只声明 App 真实支持的路径。

```json
{
  "applinks": {
    "details": [{
      "appIDs": ["TEAM_ID.com.example.CompanyApp"],
      "components": [{ "/": "/articles/*" }]
    }]
  }
}
```

请在真机测试。域名关联是否正确是 Apple 平台能力；它与 URLRouter 自己的 URL
校验是两件事。

## 下一步

- 多团队或多 Package 发布路由前，阅读[架构说明](architecture.zh-CN.md)。
- 产品需要远程限制、事故控制、遥测或并发路由时，阅读
  [生产治理](production-governance.zh-CN.md)。
