# URLRouter

[🇺🇸 English](README.md)

> iOS 17+ · Swift 6 · SwiftUI · Universal Links · 模块化 `openURL` 路由

URLRouter 是面向模块化 App 的 SwiftUI 路由基础库。Feature 页面统一使用 `openURL` 跳转；URLRouter 负责校验 URL、找到所属 Feature Package，并执行 URL 中声明的展示方式。

## 目录

1. [安装](#安装)
2. [架构](#架构)
3. [配置 Universal Link](#配置-universal-link)
4. [Feature Package](#feature-package)
5. [App Shell](#app-shell)
6. [常见路由场景](#常见路由场景)
7. [Demo 与测试](#demo-与测试)

## 安装

在 Xcode 的 **File > Add Package Dependencies…** 添加 `https://github.com/relaxfinger/URLRouter.git`，随后导入 `URLRouter`。最低支持 iOS 17。

## 架构

URLRouter 让 Feature 页面统一通过 `openURL` 跳转。App Shell 一次性注册各 Feature Package 后，使用完整 HTTPS URL 并携带必填 `presentation` query 即可。合法值为 `push`、`tab`、`sheet`、`fullScreenCover`。

```text
https://example.com/articles/42?presentation=push
https://example.com/favorites?presentation=tab
https://example.com/settings?presentation=sheet
https://example.com/sign-in?presentation=fullScreenCover
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
            guard link.pathComponents.count == 2,
                  link.pathComponents[0] == "articles" else { return nil }
            return ModuleRoute(
                moduleID: id,
                routeID: "detail",
                parameters: ["id": link.pathComponents[1]]
            )
        },
        destination: { route in
            guard route.routeID == "detail" else { return nil }
            return AnyView(ArticleView(id: route.parameters["id"] ?? ""))
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
            openURL(URL(string: "https://example.com/articles/42?presentation=push")!)
        }
    }
}
```

## App Shell

App 只链接 Feature Package 并一次性注册模块；它不解析 Feature 路径，也不选择 push/tab/sheet/全屏展示方式。

```swift
@main
struct MyApp: App {
    @State private var router = ModuleRouter()
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
                allowedHosts: ["example.com"]
            )
        }
    }
}
```

Swift 无法在运行时发现未链接的 Package。存在两个或更多 Feature Package 时，App Shell 只需将每个 Package 唯一的 `RouteModule` 放入同一个注册表。新增 Feature 时仍要链接其 Package 并注册该模块，但永远不需要改中心化 URL `switch`、路径解析或展示方式映射。

## 常见路由场景

| 业务意图 | Feature 代码 |
| --- | --- |
| Push 详情 | `openURL(URL(string: "https://example.com/articles/42?presentation=push")!)` |
| 切换 Tab | `openURL(URL(string: "https://example.com/favorites?presentation=tab")!)` |
| 展示 Sheet | `openURL(URL(string: "https://example.com/settings?presentation=sheet")!)` |
| 全屏流程 | `openURL(URL(string: "https://example.com/sign-in?presentation=fullScreenCover")!)` |

异步操作完成后，回到主线程再调用 `openURL`：

```swift
Task {
    let id = try await articleService.recommendedArticleID()
    await MainActor.run {
        openURL(URL(string: "https://example.com/articles/\(id)?presentation=push")!)
    }
}
```

## Demo 与测试

打开 `URLRouter.xcodeproj`，选择 **URLRouterDemo** scheme 与 iOS 17+ simulator 后运行。Demo 展示四种 URL 展示方式，以及直接输入 URL 的模拟功能。

运行测试：

```bash
swift test
```

## 许可证

URLRouter 使用 [MIT License](LICENSE) 发布。
