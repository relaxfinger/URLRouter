# URLRouter

> iOS 17+ · Swift 6 · SwiftUI · Universal Links

**中文**：URLRouter 是一个面向 SwiftUI 的轻量级页面路由基础库。它把外部 URL 转成强类型的路由值，再由每个窗口自己的路由状态驱动 Tab、页面 push、sheet 和全屏页面。它不寻找“最上层 ViewController”，因此适用于多窗口和纯 SwiftUI App。

**English**: URLRouter is a lightweight SwiftUI routing foundation. It converts external URLs into strongly typed route values, then uses scene-local state to drive tabs, pushes, sheets, and full-screen covers. It never searches for a global “top view controller”, so it works naturally with multi-window SwiftUI apps.

## Table of contents / 目录

1. [Requirements and installation / 前置条件与安装](#requirements-and-installation--前置条件与安装)
2. [How it works / 工作原理](#how-it-works--工作原理)
3. [Set up Universal Links / 配置 Universal Link](#set-up-universal-links--配置-universal-link)
4. [Complete first integration / 完整首次接入](#complete-first-integration--完整首次接入)
5. [Routing scenarios / 常见路由场景](#routing-scenarios--常见路由场景)
6. [Validation, errors, and security / 校验、错误与安全](#validation-errors-and-security--校验错误与安全)
7. [Testing and troubleshooting / 测试与排错](#testing-and-troubleshooting--测试与排错)

## Requirements and installation / 前置条件与安装

| Requirement | 中文 | English |
| --- | --- | --- |
| Deployment target | iOS 17 或更高版本 | iOS 17 or later |
| Language mode | Swift 6（建议启用 Strict Concurrency Checking） | Swift 6 (strict concurrency checking recommended) |
| UI | SwiftUI；库内部使用 `NavigationStack` 和 Observation | SwiftUI; the library uses `NavigationStack` and Observation |

### Swift Package Manager / 使用 SPM

**中文**：在 Xcode 选择 **File > Add Package Dependencies…**，输入仓库地址：

```text
https://github.com/relaxfinger/URLRouter.git
```

将 `URLRouter` 添加到你的 App target，然后导入模块：

```swift
import URLRouter
```

**English**: In Xcode choose **File > Add Package Dependencies…**, paste the repository URL above, add `URLRouter` to your app target, then import it as shown.

## How it works / 工作原理

```text
https://example.com/articles/42
              │
              ▼
 UniversalLink (validates URL, host, path, query)
              │
              ▼
 AppRoute.presentation(for:) (your URL grammar)
              │
              ▼
 RoutePresentation (push / tab / sheet / full screen)
              │
              ▼
 AppRouter (one instance per WindowGroup)
              │
              ▼
 RouterHost + NavigationStack + your SwiftUI views
```

**中文**：`AppRoute` 是你的页面和参数的唯一真相来源。URL 解析只产生数据，不直接创建 View；`AppRouter` 只在主线程更新 UI 状态。

**English**: `AppRoute` is the single source of truth for screens and their parameters. URL parsing only produces data—it never creates a view. `AppRouter` updates UI state only on the main actor.

## Set up Universal Links / 配置 Universal Link

URLRouter **不能替代** Apple 的 Universal Link 配置。下面三步都必须完成。

### 1. Add the Associated Domains capability / 添加 Associated Domains

在 App target 的 **Signing & Capabilities** 中：

1. 点击 **+ Capability**。
2. 添加 **Associated Domains**。
3. 在 Domains 列表加入 `applinks:example.com`。

**注意 / Note**：只填写域名，不要带 `https://`、路径、query 或结尾的 `/`。`example.com` 和 `www.example.com` 是两个不同的域名；需要时都要添加。

### 2. Host `apple-app-site-association` / 部署关联文件

在服务器公开部署以下无扩展名文件：

```text
https://example.com/.well-known/apple-app-site-association
```

示例（请替换 `TEAM_ID` 和 bundle ID）：

```json
{
  "applinks": {
    "details": [
      {
        "appIDs": ["TEAM_ID.com.example.MyApp"],
        "components": [
          { "/": "/articles/*" },
          { "/": "/settings" },
          { "/": "/sign-in" }
        ]
      }
    ]
  }
}
```

**中文检查项**：文件必须走有效 HTTPS、不能重定向、域名必须公开可访问。`TEAM_ID` 可以在 Apple Developer account 或 App 的签名信息中找到。

**English checklist**: Serve the file over valid HTTPS with no redirect, from a publicly reachable domain. Find `TEAM_ID` in your Apple Developer account or signing information.

Apple 会验证 App entitlement 与该文件的双向关联；详情见 [Supporting Associated Domains](https://developer.apple.com/documentation/Xcode/supporting-associated-domains?changes=_2)。

### 3. Receive the URL in SwiftUI / 在 SwiftUI 中接收 URL

将 `.onOpenURL` 放在 `WindowGroup` 内的根视图上。它会把系统传入的 URL 交给路由器。完整可运行的结构见下一节。

## Complete first integration / 完整首次接入

以下示例涵盖首页 Tab、文章详情、设置 sheet 和登录全屏页。把 `example.com` 替换为你的真实域名。

### Step 1 — Define your routes / 定义路由

```swift
import URLRouter

enum AppRoute: Hashable, Sendable, UniversalLinkRoute {
    // Tab roots / Tab 根页面
    case home
    case favorites

    // Destinations / 具体页面
    case article(id: String)
    case settings
    case signIn

    static func presentation(for link: UniversalLink) throws -> RoutePresentation<AppRoute> {
        // https://example.com -> Home tab
        if link.pathComponents.isEmpty {
            return .selectTab(.home)
        }

        // https://example.com/articles/42 -> push article 42
        if link.pathComponents.count == 2,
           link.pathComponents[0] == "articles",
           !link.pathComponents[1].isEmpty {
            return .push(.article(id: link.pathComponents[1]))
        }

        // https://example.com/settings -> present a sheet
        if link.pathComponents == ["settings"] {
            return .sheet(.settings)
        }

        // https://example.com/sign-in -> present full-screen login
        if link.pathComponents == ["sign-in"] {
            return .fullScreenCover(.signIn)
        }

        throw UniversalLinkError.unsupportedRoute
    }
}
```

**中文**：这里是唯一需要认识 URL 路径的地方。`/articles/42` 的 `42` 会作为 `.article(id:)` 的参数。不能识别的 URL 必须抛出 `unsupportedRoute`，不要静默跳去首页。

**English**: This is the only place that needs to know URL paths. The `42` in `/articles/42` becomes the parameter of `.article(id:)`. Throw `unsupportedRoute` for an unrecognized URL instead of silently navigating home.

### Step 2 — Create one router for each window / 每个窗口创建一个 router

```swift
import SwiftUI
import URLRouter

@main
struct MyApp: App {
    @State private var router = AppRouter<AppRoute>()

    var body: some Scene {
        WindowGroup {
            RouterHost(router: router) {
                AppTabs(router: router)
            } destination: { route in
                RouteDestination(route: route)
            }
            .onOpenURL { url in
                do {
                    try router.handle(
                        universalLink: url,
                        allowedHosts: ["example.com"]
                    )
                } catch {
                    // Replace with your logger/analytics in production.
                    print("Ignored Universal Link: \(url), error: \(error)")
                }
            }
        }
    }
}
```

**中文**：不要写 `static let shared`。每个 `WindowGroup` 都应拥有自己的 `AppRouter`，这样 iPad 多窗口不会互相修改导航栈。

**English**: Do not create a `static let shared` router. Each `WindowGroup` needs its own `AppRouter`, so separate iPad windows don’t change each other’s navigation stacks.

### Step 3 — Build tabs and destinations / 实现 Tab 与目标页面

```swift
struct AppTabs: View {
    @Bindable var router: AppRouter<AppRoute>

    var body: some View {
        TabView(selection: $router.selectedTab) {
            HomeView(router: router)
                .tabItem { Label("Home", systemImage: "house") }
                .tag(Optional(AppRoute.home))

            FavoritesView()
                .tabItem { Label("Favorites", systemImage: "heart") }
                .tag(Optional(AppRoute.favorites))
        }
    }
}

struct RouteDestination: View {
    let route: AppRoute

    @ViewBuilder
    var body: some View {
        switch route {
        case .article(let id):
            ArticleView(id: id)
        case .settings:
            SettingsView()
        case .signIn:
            SignInView()
        case .home, .favorites:
            EmptyView() // Tab roots are not pushed as destinations.
        }
    }
}

struct HomeView: View {
    let router: AppRouter<AppRoute>

    var body: some View {
        Button("Open article 42") {
            router.apply(.push(.article(id: "42")))
        }
    }
}
```

**中文**：`RouterHost` 已经创建了 `NavigationStack`，不要再在 `HomeView` 中嵌套一个新的 `NavigationStack`。

**English**: `RouterHost` already creates the `NavigationStack`; do not nest another one inside `HomeView`.

## Routing scenarios / 常见路由场景

所有示例假设当前 View 已拿到 `let router: AppRouter<AppRoute>`。

### 1. Push a detail page / Push 到详情页

```swift
// From a tap, notification, or a parsed Universal Link
router.apply(.push(.article(id: "42")))
```

**中文**：这会把文章追加到 `NavigationStack`。用户可以使用系统返回按钮或边缘滑动返回。

**English**: This appends the article to `NavigationStack`. The user can return with the system back button or edge-swipe gesture.

### 2. Switch a tab / 切换 Tab

```swift
// Switch to Favorites and clear any pushed detail pages.
router.apply(.selectTab(.favorites))

// Keep the current navigation stack when changing tab.
router.apply(.selectTab(.favorites, resetNavigation: false))
```

**中文**：Tab 的 `.tag` 必须是 `Optional(AppRoute.favorites)`，因为 `selectedTab` 的类型是 `AppRoute?`。

**English**: The tab tag must be `Optional(AppRoute.favorites)` because `selectedTab` has type `AppRoute?`.

### 3. Present and dismiss settings / 展示与关闭设置 sheet

```swift
// Present / 展示
router.apply(.sheet(.settings))

// Dismiss programmatically / 代码关闭
router.dismissSheet()
```

用户下滑关闭 sheet 时，`RouterHost` 也会自动清除状态。`RouteDestination` 会复用同一套 destination 映射显示 `SettingsView`。

When a user swipes down to dismiss, `RouterHost` also clears the state automatically. `RouteDestination` reuses the same destination mapping to show `SettingsView`.

### 4. Present a full-screen flow / 展示全屏流程

```swift
router.apply(.fullScreenCover(.signIn))

// After successful sign-in / 登录成功后
router.dismissFullScreenCover()
```

**中文**：适合登录、首次引导、支付等不希望用户看到底层内容的流程。

**English**: Use this for login, onboarding, payment, or any flow that should cover the underlying content.

### 5. Replace the navigation stack / 替换导航栈

```swift
// Example: restore a deep navigation path after login.
router.apply(.replaceStack([
    .article(id: "42"),
    .article(id: "43")
]))

// Return to the selected tab root.
router.popToRoot()
```

**中文**：`replaceStack` 适合恢复状态或一次性跳到确定的层级；一般的点击跳转请优先用 `.push`。

**English**: Use `replaceStack` for restoration or jumping to a known hierarchy. Prefer `.push` for ordinary user-driven navigation.

### 6. Guard a protected link / 对需要登录的链接做拦截

先解析并校验 URL，再决定是否允许最终路由。不要因为 URL 含有用户 ID 就信任它；请在服务端或会话层验证权限。

Parse and validate the URL first, then decide whether to allow the resulting route. Never trust a user ID merely because it appears in a URL; validate authorization with your session or server.

```swift
@MainActor
func openProtectedLink(_ url: URL, router: AppRouter<AppRoute>, isSignedIn: Bool) {
    do {
        let link = try UniversalLink(url: url, allowedHosts: ["example.com"])
        let presentation = try AppRoute.presentation(for: link)

        guard isSignedIn else {
            // In a real app, store `presentation` as a pending route, then
            // apply it after SignInView reports success.
            router.apply(.fullScreenCover(.signIn))
            return
        }

        router.apply(presentation)
    } catch {
        print("Rejected link: \(error)")
    }
}
```

### 7. Navigate after async work / 异步任务完成后跳转

```swift
Button("Load recommended article") {
    Task {
        let articleID = try await articleService.recommendedArticleID()
        // AppRouter is @MainActor, so hop back before changing UI state.
        await MainActor.run {
            router.apply(.push(.article(id: articleID)))
        }
    }
}
```

**中文**：网络和数据库工作放在 `Task` 中；只有 `router.apply` 需要回到主线程。

**English**: Perform networking and database work in `Task`; only `router.apply` needs to return to the main actor.

## Validation, errors, and security / 校验、错误与安全

`UniversalLink(url:allowedHosts:)` 在路由前执行以下检查：

| Check / 检查项 | Why / 原因 |
| --- | --- |
| HTTPS only | Universal Links must be HTTPS / Universal Link 必须使用 HTTPS |
| Exact allowed host | Blocks links from untrusted domains / 拒绝未受信任域名 |
| No credentials or non-default port | Avoids ambiguous or unsafe URL forms / 避免歧义和危险 URL |
| No fragment | Keeps a single canonical route input / 保持唯一规范输入 |
| Decoded path segments | Prevents encoded `/` from changing path structure / 防止编码 `/` 改变路径结构 |
| Unique query items with values | Avoids `?id=1&id=2` ambiguity / 避免重复参数歧义 |

可针对具体错误处理：

```swift
do {
    try router.handle(universalLink: url, allowedHosts: ["example.com"])
} catch UniversalLinkError.untrustedHost {
    // Ignore and optionally record a security event.
} catch UniversalLinkError.unsupportedRoute {
    // Show a friendly "This link is no longer available" view if appropriate.
} catch {
    // Log malformed links for diagnostics.
}
```

Apple 也明确建议把 Universal Link 视为外部输入并验证所有参数：[Supporting Universal Links in Your App](https://developer.apple.com/documentation/xcode/supporting-universal-links-in-your-app?language=objc)。

## Testing and troubleshooting / 测试与排错

### Unit-test the URL grammar / 测试 URL 语法

你的路由 enum 是纯数据逻辑，因此不需要启动 App 即可测试：

```swift
func testArticleLinkBecomesPush() throws {
    let link = try UniversalLink(
        url: try XCTUnwrap(URL(string: "https://example.com/articles/42")),
        allowedHosts: ["example.com"]
    )

    XCTAssertEqual(
        try AppRoute.presentation(for: link),
        .push(.article(id: "42"))
    )
}
```

> `RoutePresentation` is intentionally `Sendable`, but it is not `Equatable`. If you want the exact assertion above, add an `Equatable` adapter in your app or switch over the result and assert its associated route. / `RoutePresentation` 有意只保证 `Sendable`，未声明 `Equatable`。如需完全相等断言，请在 App 内增加适配层，或对结果 `switch` 后断言关联的 route。

推荐的可编译版本：

```swift
let presentation = try AppRoute.presentation(for: link)
if case .push(.article(let id)) = presentation {
    XCTAssertEqual(id, "42")
} else {
    XCTFail("Expected an article push")
}
```

### Test Universal Links on a device / 在真机测试

1. 先确认 AASA 文件能通过浏览器直接访问：`https://example.com/.well-known/apple-app-site-association`。
2. 删除并重新安装 App（系统会在安装时验证关联）。
3. 将完整链接粘贴到“备忘录”或“信息”中后点击/长按测试。
4. 不要只在 Safari 地址栏手动输入 URL；这通常仍被视为浏览器内直接导航。

Apple 的 [TN3155: Debugging Universal Links](https://developer.apple.com/documentation/technotes/tn3155-debugging-universal-links/) 提供了真机诊断步骤和更多排错方法。

### Common mistakes / 常见错误

| Symptom / 现象 | Check / 检查 |
| --- | --- |
| Link opens Safari | Associated Domains entitlement、AASA 的 `appIDs`、HTTPS 和无重定向；重新安装 App 后再试。 |
| `.onOpenURL` runs but no page changes | 检查 `allowedHosts`、`pathComponents`、以及 `AppRoute.presentation(for:)` 是否抛出了错误。 |
| A detail page is shown twice | 不要同时在 feature View 内和 `RouterHost` 外各创建一个 `NavigationStack`。 |
| Wrong tab is selected | 用 `Optional(AppRoute.someTab)` 作为 `.tag`，并确保 route case 与 `selectedTab` 一致。 |
| Push from a background task fails | 在 `await MainActor.run { router.apply(...) }` 中更新 router。 |

## API quick reference / API 速查

| API | Use / 用途 |
| --- | --- |
| `UniversalLink(url:allowedHosts:)` | Validate and split an incoming HTTPS URL / 校验并拆解传入 URL |
| `UniversalLinkRoute` | Map a validated URL to a typed presentation / 映射 URL 到强类型跳转 |
| `RoutePresentation.push` | Push a page / push 页面 |
| `RoutePresentation.selectTab` | Select a Tab, optionally clearing the stack / 选择 Tab，可选择清空导航栈 |
| `RoutePresentation.sheet` | Present a sheet / 展示 sheet |
| `RoutePresentation.fullScreenCover` | Present a full-screen flow / 展示全屏流程 |
| `RoutePresentation.replaceStack` | Restore or replace a whole path / 恢复或替换完整路径 |
| `AppRouter.apply(_:)` | Execute a route presentation / 执行跳转 |
| `AppRouter.handle(universalLink:allowedHosts:)` | Validate, parse, and execute a Universal Link / 校验、解析并执行 Universal Link |
| `RouterHost` | Connect router state to SwiftUI presentation / 把 router 状态接到 SwiftUI 展示 |
