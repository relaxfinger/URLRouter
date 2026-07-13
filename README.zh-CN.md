# URLRouter

[🇺🇸 English](README.md)

> iOS 17+ · Swift 6 · SwiftUI · Universal Links

URLRouter 是一个面向 SwiftUI 的轻量级页面路由基础库。它先将外部 URL 转成强类型路由值，再由每个窗口自己的路由状态驱动 Tab、页面 push、sheet 和全屏页面。它不再寻找“最上层 ViewController”，因此适合多窗口和纯 SwiftUI App。

## 目录

1. [前置条件与安装](#前置条件与安装)
2. [工作原理](#工作原理)
3. [配置 Universal Link](#配置-universal-link)
4. [完整首次接入](#完整首次接入)
5. [常见路由场景](#常见路由场景)
6. [示例应用](#示例应用)
7. [校验、错误与安全](#校验错误与安全)
8. [测试与排错](#测试与排错)

## 前置条件与安装

- 最低系统：iOS 17。
- 语言版本：Swift 6，建议开启 Strict Concurrency Checking。
- UI：SwiftUI；库内部使用 `NavigationStack` 和 Observation。

### 使用 Swift Package Manager

在 Xcode 选择 **File > Add Package Dependencies…**，输入：

```text
https://github.com/relaxfinger/URLRouter.git
```

将 `URLRouter` 添加到你的 App target，然后导入模块：

```swift
import URLRouter
```

## 工作原理

```text
https://example.com/articles/42
              │
              ▼
UniversalLink：校验并拆分 URL
              │
              ▼
AppRoute.presentation(for:)：定义业务 URL 语法
              │
              ▼
RoutePresentation：描述展示方式
              │
              ▼
AppRouter：保存导航状态
              │
              ▼
RouterHost：渲染为 SwiftUI 页面
```

`AppRoute` 是页面和参数的唯一真相来源。URL 解析只产生数据，不直接创建 View；`AppRouter` 只在主线程更新 UI 状态。

## 配置 Universal Link

URLRouter 不能替代 Apple 的 Universal Link 配置。以下三步都必须完成。

### 1. 添加 Associated Domains

在 App target 的 **Signing & Capabilities** 中：

1. 点击 **+ Capability**。
2. 添加 **Associated Domains**。
3. 在 Domains 列表加入 `applinks:example.com`。

只填写域名，不要带 `https://`、路径、query 或结尾的 `/`。`example.com` 和 `www.example.com` 是不同域名，需要时都要添加。

### 2. 部署 apple-app-site-association

在服务器公开部署无扩展名文件：

```text
https://example.com/.well-known/apple-app-site-association
```

示例，请替换 `TEAM_ID` 和 bundle ID：

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

文件必须使用有效 HTTPS、不能重定向、域名必须能从公网访问。关联文件与 entitlement 需要一致。详见 Apple 的 [Supporting Associated Domains](https://developer.apple.com/documentation/Xcode/supporting-associated-domains?changes=_2)。

### 3. 在 SwiftUI 接收 URL

将 `.onOpenURL` 放在 `WindowGroup` 内的根视图。完整代码见下一节。

## 完整首次接入

下面的例子包含首页 Tab、文章详情、设置 sheet 和全屏登录页。请将 `example.com` 替换为你的真实域名。

### 第一步：定义路由

```swift
import URLRouter

enum AppRoute: Hashable, Sendable, UniversalLinkRoute {
    case home
    case favorites
    case article(id: String)
    case settings
    case signIn

    static func presentation(for link: UniversalLink) throws -> RoutePresentation<AppRoute> {
        if link.pathComponents.isEmpty {
            return .selectTab(.home)
        }
        if link.pathComponents == ["favorites"] {
            return .selectTab(.favorites)
        }
        if link.pathComponents.count == 2,
           link.pathComponents[0] == "articles",
           !link.pathComponents[1].isEmpty {
            return .push(.article(id: link.pathComponents[1]))
        }
        if link.pathComponents == ["settings"] {
            return .sheet(.settings)
        }
        if link.pathComponents == ["sign-in"] {
            return .fullScreenCover(.signIn)
        }
        throw UniversalLinkError.unsupportedRoute
    }
}
```

这是唯一需要认识 URL 路径的地方。`/articles/42` 中的 `42` 会成为 `.article(id:)` 的参数。不能识别的 URL 应抛出 `unsupportedRoute`，不要静默跳转到首页。

### 第二步：为每个窗口创建 router

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
                    try router.handle(universalLink: url, allowedHosts: ["example.com"])
                } catch {
                    print("Ignored Universal Link: \(url), error: \(error)")
                }
            }
        }
    }
}
```

不要创建 `static let shared` 全局 router。每个 `WindowGroup` 应拥有自己的 `AppRouter`，这样 iPad 多窗口不会互相修改导航栈。

### 第三步：实现 Tab 和目标页面

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
        case .article(let id): ArticleView(id: id)
        case .settings: SettingsView()
        case .signIn: SignInView()
        case .home, .favorites: EmptyView()
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

`RouterHost` 已经创建了 `NavigationStack`，不要再在 `HomeView` 中嵌套新的 `NavigationStack`。

## 常见路由场景

以下例子假设当前 View 已拿到 `let router: AppRouter<AppRoute>`。

### Push 到详情页

```swift
router.apply(.push(.article(id: "42")))
```

这会把文章追加到 `NavigationStack`。用户可以使用系统返回按钮或边缘滑动返回。

### 切换 Tab

```swift
// 切换到收藏，并清空当前 push 栈。
router.apply(.selectTab(.favorites))

// 切换 Tab 时保留当前 push 栈。
router.apply(.selectTab(.favorites, resetNavigation: false))
```

Tab 的 `.tag` 必须使用 `Optional(AppRoute.favorites)`，因为 `selectedTab` 的类型是 `AppRoute?`。

### 展示与关闭设置 Sheet

```swift
router.apply(.sheet(.settings))
router.dismissSheet()
```

用户下滑关闭 sheet 时，`RouterHost` 也会自动清除状态。

### 展示全屏流程

```swift
router.apply(.fullScreenCover(.signIn))

// 登录成功后
router.dismissFullScreenCover()
```

适合登录、首次引导、支付等不希望用户看到底层内容的流程。

### 替换整个导航栈

```swift
router.apply(.replaceStack([
    .article(id: "42"),
    .article(id: "43")
]))

router.popToRoot()
```

`replaceStack` 适合状态恢复或一次性跳转到明确的层级；普通点击跳转优先使用 `.push`。

### 对需要登录的链接做拦截

先解析并校验 URL，再决定是否允许最终路由。不要因为 URL 带有用户 ID 就信任它；仍需使用会话或服务端验证权限。

```swift
@MainActor
func openProtectedLink(_ url: URL, router: AppRouter<AppRoute>, isSignedIn: Bool) {
    do {
        let link = try UniversalLink(url: url, allowedHosts: ["example.com"])
        let presentation = try AppRoute.presentation(for: link)

        guard isSignedIn else {
            // 真实项目中保存 presentation；登录成功后再执行它。
            router.apply(.fullScreenCover(.signIn))
            return
        }

        router.apply(presentation)
    } catch {
        print("Rejected link: \(error)")
    }
}
```

### 异步任务完成后跳转

```swift
Button("Load recommended article") {
    Task {
        let articleID = try await articleService.recommendedArticleID()
        await MainActor.run {
            router.apply(.push(.article(id: articleID)))
        }
    }
}
```

网络和数据库工作放在 `Task` 中；只有 `router.apply` 需要回到主线程。

## 示例应用

仓库包含可直接运行的 [URLRouterDemo](URLRouterDemo) target。打开 `URLRouter.xcodeproj`，在 Scheme 菜单选择 **URLRouterDemo**，选择一个 iOS 17+ Simulator 后运行。

Demo 展示：

- 本地按钮触发 push、Tab、sheet 和 full-screen cover；
- 输入 URL 后直接模拟系统传入的 Universal Link；
- `/articles/private` 触发登录拦截，并在“登录成功”后恢复原跳转；
- `example.com` 是占位域名。Simulator 的“Route this URL”不依赖 AASA；真机真实 Universal Link 测试前，必须替换 entitlement、`allowedHosts`、AASA 文件中的域名和 App ID。

## 校验、错误与安全

`UniversalLink(url:allowedHosts:)` 会在路由前检查：

| 检查项 | 原因 |
| --- | --- |
| 仅 HTTPS | Universal Link 必须使用 HTTPS。 |
| 精确允许的 host | 拒绝未受信任域名。 |
| 禁止凭据与非默认端口 | 避免歧义和危险 URL。 |
| 禁止 fragment | 保持唯一规范输入。 |
| 解码 path segment | 防止编码 `/` 改变路径结构。 |
| query 必须唯一且有值 | 避免 `?id=1&id=2` 的歧义。 |

可以针对具体错误处理：

```swift
do {
    try router.handle(universalLink: url, allowedHosts: ["example.com"])
} catch UniversalLinkError.untrustedHost {
    // 忽略，并按需记录安全事件。
} catch UniversalLinkError.unsupportedRoute {
    // 按需展示“链接已失效”。
} catch {
    // 记录格式错误的链接，供排错使用。
}
```

Apple 建议将 Universal Link 作为外部输入并校验所有参数：[Supporting Universal Links in Your App](https://developer.apple.com/documentation/xcode/supporting-universal-links-in-your-app?language=objc)。

## 测试与排错

### 测试 URL 语法

路由 enum 是纯数据逻辑，无需启动 App 即可测试：

```swift
func testArticleLinkBecomesPush() throws {
    let link = try UniversalLink(
        url: try XCTUnwrap(URL(string: "https://example.com/articles/42")),
        allowedHosts: ["example.com"]
    )

    let presentation = try AppRoute.presentation(for: link)
    if case .push(.article(let id)) = presentation {
        XCTAssertEqual(id, "42")
    } else {
        XCTFail("Expected an article push")
    }
}
```

### 在真机测试 Universal Link

1. 确认 AASA 文件可直接访问：`https://example.com/.well-known/apple-app-site-association`。
2. 删除并重新安装 App。
3. 将完整链接粘贴到“备忘录”或“信息”中，点击或长按测试。
4. 不要只在 Safari 地址栏手动输入 URL；这通常仍被视为浏览器内直接导航。

Apple 的 [TN3155: Debugging Universal Links](https://developer.apple.com/documentation/technotes/tn3155-debugging-universal-links/) 提供了更多真机诊断步骤。

### 常见错误

| 现象 | 检查项 |
| --- | --- |
| 链接打开 Safari | 检查 Associated Domains、AASA 的 `appIDs`、HTTPS、无重定向，并重新安装 App。 |
| `.onOpenURL` 已调用但页面不变 | 检查 `allowedHosts`、`pathComponents` 和 `AppRoute.presentation(for:)` 抛出的错误。 |
| 详情页展示两次 | 不要在 feature View 内和 `RouterHost` 外分别创建 `NavigationStack`。 |
| Tab 选择错误 | 使用 `Optional(AppRoute.someTab)` 作为 `.tag`。 |
| 后台任务中的跳转失败 | 使用 `await MainActor.run { router.apply(...) }` 更新 router。 |

## 许可证

URLRouter 使用 [MIT License](LICENSE) 发布。你可以自由使用、复制、修改、分发及用于商业项目；分发代码或其重要部分时，请保留版权与许可证声明。软件按“原样”提供，不附带任何担保。详见 [LICENSE](LICENSE)。
