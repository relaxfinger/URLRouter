# URLRouter

iOS 17+ SwiftUI 路由基础库：将 Universal Link 解析为强类型 `Route`，并由每个
`WindowGroup` 自己的 `@MainActor @Observable` `AppRouter` 驱动导航状态。

## 接入方式

1. 在**应用 Target**启用 Associated Domains，加入 `applinks:example.com`，并在该
   HTTPS 域名部署正确的 `apple-app-site-association`。该 entitlement 和服务器文件不属于库。
2. 用 App 自己的 route enum 定义 URL 语法：

```swift
enum AppRoute: Hashable, Sendable, UniversalLinkRoute {
    case home
    case product(id: String)
    case settings

    static func presentation(for link: UniversalLink) throws -> RoutePresentation<AppRoute> {
        if link.pathComponents.isEmpty { return .selectTab(.home) }
        if link.pathComponents.count == 2,
           link.pathComponents[0] == "products",
           !link.pathComponents[1].isEmpty {
            return .push(.product(id: link.pathComponents[1]))
        }
        if link.pathComponents == ["settings"] { return .sheet(.settings) }
        throw UniversalLinkError.unsupportedRoute
    }
}
```

3. 每个 `WindowGroup` 保有一个 router；不要再全局寻找 window 或 top-most controller：

```swift
@main
struct ExampleApp: App {
    @State private var router = AppRouter<AppRoute>()

    var body: some Scene {
        WindowGroup {
            RouterHost(router: router) {
                HomeView()
            } destination: { route in
                DestinationView(route: route)
            }
            .onOpenURL { url in
                try? router.handle(universalLink: url, allowedHosts: ["example.com"])
            }
        }
    }
}
```

`RouterHost` 负责 `NavigationStack`、sheet、full-screen cover。Tab 场景将
`router.selectedTab` 绑定到根 `TabView` 的 selection，并用
`.selectTab(_, resetNavigation:)` 切换。鉴权、预取等异步任务在调用 `apply(_:)` 前完成。
