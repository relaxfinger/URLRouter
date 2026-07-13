# URLRouter

[🇨🇳 Chinese](README.zh-CN.md)

> iOS 17+ · Swift 6 · SwiftUI · Universal Links

URLRouter is a lightweight SwiftUI routing foundation. It converts external URLs into strongly typed route values, then uses scene-local state to drive tabs, pushes, sheets, and full-screen covers. It never searches for a global “top view controller”, which makes it suitable for multi-window and pure SwiftUI apps.

## Contents

1. [Requirements and installation](#requirements-and-installation)
2. [How it works](#how-it-works)
3. [Set up Universal Links](#set-up-universal-links)
4. [Complete first integration](#complete-first-integration)
5. [Routing scenarios](#routing-scenarios)
6. [Modular feature packages](#modular-feature-packages)
7. [Demo app](#demo-app)
8. [Validation, errors, and security](#validation-errors-and-security)
9. [Testing and troubleshooting](#testing-and-troubleshooting)

## Requirements and installation

- Deployment target: iOS 17 or later.
- Language mode: Swift 6; strict concurrency checking is recommended.
- UI: SwiftUI. The library uses `NavigationStack` and Observation internally.

### Swift Package Manager

In Xcode, choose **File > Add Package Dependencies…** and enter:

```text
https://github.com/relaxfinger/URLRouter.git
```

Add `URLRouter` to the app target, then import it:

```swift
import URLRouter
```

## How it works

```text
https://example.com/articles/42
              │
              ▼
UniversalLink: validates and splits the URL
              │
              ▼
AppRoute.presentation(for:): your URL grammar
              │
              ▼
RoutePresentation: how the route should be shown
              │
              ▼
AppRouter: scene navigation state
              │
              ▼
RouterHost: SwiftUI presentation
```

`AppRoute` is the single source of truth for screens and parameters. URL parsing only creates data, never views. `AppRouter` updates UI state on the main actor.

## Set up Universal Links

URLRouter does not replace Apple’s Universal Link setup. Complete all three steps below.

### 1. Add Associated Domains

In the app target’s **Signing & Capabilities** tab:

1. Click **+ Capability**.
2. Add **Associated Domains**.
3. Add `applinks:example.com` to the Domains list.

Enter only the domain: no `https://`, path, query, or trailing `/`. `example.com` and `www.example.com` are different domains, and both must be listed when needed.

### 2. Host apple-app-site-association

Publish an extensionless file at:

```text
https://example.com/.well-known/apple-app-site-association
```

Replace `TEAM_ID` and the bundle ID in this example:

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

The file must use valid HTTPS, have no redirects, and be publicly reachable. The associated-domain entitlement and this file must agree. See Apple’s [Supporting Associated Domains](https://developer.apple.com/documentation/Xcode/supporting-associated-domains?changes=_2).

### 3. Receive the URL in SwiftUI

Put `.onOpenURL` on the root view inside `WindowGroup`. The complete setup is below.

## Complete first integration

This example contains a home tab, article details, a settings sheet, and a full-screen sign-in screen. Replace `example.com` with your domain.

### Step 1: Define routes

```swift
import URLRouter

enum AppRoute: Hashable, Sendable, UniversalLinkRoute {
    case home
    case favorites
    case article(id: String)
    case settings
    case signIn

    static func presentation(for link: UniversalLink) throws -> RoutePresentation<AppRoute> {
        if link.pathComponents.isEmpty { return .selectTab(.home) }
        if link.pathComponents == ["favorites"] { return .selectTab(.favorites) }
        if link.pathComponents.count == 2,
           link.pathComponents[0] == "articles",
           !link.pathComponents[1].isEmpty {
            return .push(.article(id: link.pathComponents[1]))
        }
        if link.pathComponents == ["settings"] { return .sheet(.settings) }
        if link.pathComponents == ["sign-in"] { return .fullScreenCover(.signIn) }
        throw UniversalLinkError.unsupportedRoute
    }
}
```

This is the only place that needs to know URL paths. The `42` in `/articles/42` becomes the `.article(id:)` parameter. Throw `unsupportedRoute` for unknown URLs instead of silently navigating home.

### Step 2: Create one router per window

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

Do not create a global `static let shared` router. Each `WindowGroup` needs its own `AppRouter`, so separate iPad windows cannot alter each other’s navigation state.

### Step 3: Build tabs and destinations

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
```

`RouterHost` already creates `NavigationStack`; do not nest another `NavigationStack` inside `HomeView`.

## Routing scenarios

Assume the current view has `let router: AppRouter<AppRoute>`.

### Push a detail page

```swift
router.apply(.push(.article(id: "42")))
```

The route is appended to `NavigationStack`. Users return using the system back button or edge-swipe gesture.

### Switch tabs

```swift
router.apply(.selectTab(.favorites))
router.apply(.selectTab(.favorites, resetNavigation: false))
```

The tab tag must be `Optional(AppRoute.favorites)` because `selectedTab` is `AppRoute?`.

### Present and dismiss a sheet

```swift
router.apply(.sheet(.settings))
router.dismissSheet()
```

When the user swipes down, `RouterHost` clears the sheet state automatically.

### Present a full-screen flow

```swift
router.apply(.fullScreenCover(.signIn))
router.dismissFullScreenCover()
```

Use this for sign-in, onboarding, payment, or flows that should fully cover the underlying content.

### Replace the navigation stack

```swift
router.apply(.replaceStack([
    .article(id: "42"),
    .article(id: "43")
]))
router.popToRoot()
```

Use `replaceStack` for restoration or a jump to a known hierarchy. Prefer `.push` for ordinary taps.

### Guard a protected link

Parse and validate the URL first. A user ID in a URL is not authorization; validate permissions with the session or server.

```swift
@MainActor
func openProtectedLink(_ url: URL, router: AppRouter<AppRoute>, isSignedIn: Bool) {
    do {
        let link = try UniversalLink(url: url, allowedHosts: ["example.com"])
        let presentation = try AppRoute.presentation(for: link)
        guard isSignedIn else {
            // Store presentation and apply it after a successful sign-in.
            router.apply(.fullScreenCover(.signIn))
            return
        }
        router.apply(presentation)
    } catch {
        print("Rejected link: \(error)")
    }
}
```

### Navigate after asynchronous work

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

Perform networking and database work in `Task`; only `router.apply` needs to return to the main actor.

## Modular feature packages

Only the app shell needs `URLRouter`. A feature package can depend on `SwiftUI` alone and request navigation through the system `openURL` environment action:

```swift
import SwiftUI

struct ArticleList: View {
    @Environment(\.openURL) private var openURL

    var body: some View {
        Button("Open article 42") {
            openURL(URL(string: "https://example.com/articles/42")!)
        }
    }
}
```

Install a router-backed action at the app root. This adapter handles approved internal hosts and leaves every other URL to the operating system:

```swift
RouterHost(router: router) {
    AppTabs()
} destination: { route in
    RouteDestination(route: route)
}
.environment(
    \.openURL,
    router.openURLAction(allowedHosts: ["example.com"])
)
.onOpenURL { url in
    try? router.handle(universalLink: url, allowedHosts: ["example.com"])
}
```

The feature never imports `URLRouter`, accesses `AppRouter`, or knows whether a URL becomes a push, tab, sheet, or full-screen presentation. For authentication, analytics, or error reporting, replace `openURLAction` with a small app-shell `OpenURLAction` wrapper; the demo includes one that protects `/articles/private`.

## Demo app

The repository includes a runnable [URLRouterDemo](URLRouterDemo) target. Open `URLRouter.xcodeproj`, select the **URLRouterDemo** scheme, choose an iOS 17+ simulator, and run it.

The demo includes local push, tab, sheet, and full-screen routes; direct URL simulation; and a protected `/articles/private` route that resumes after a simulated sign-in. `example.com` is a placeholder. URL simulation does not require AASA, but device testing of real Universal Links does: replace the domain in entitlements, `allowedHosts`, and the AASA file.

## Validation, errors, and security

`UniversalLink(url:allowedHosts:)` checks the following before routing:

| Check | Reason |
| --- | --- |
| HTTPS only | Universal Links require HTTPS. |
| Exact allowed host | Rejects untrusted domains. |
| No credentials or non-default port | Avoids ambiguous and unsafe URL forms. |
| No fragment | Maintains one canonical routing input. |
| Decoded path segments | Prevents encoded `/` from changing the route hierarchy. |
| Unique query values | Avoids ambiguous inputs such as `?id=1&id=2`. |

```swift
do {
    try router.handle(universalLink: url, allowedHosts: ["example.com"])
} catch UniversalLinkError.untrustedHost {
    // Ignore and optionally log a security event.
} catch UniversalLinkError.unsupportedRoute {
    // Show a friendly unavailable-link screen if appropriate.
} catch {
    // Log malformed links for diagnostics.
}
```

Apple recommends treating Universal Links as external input and validating every parameter: [Supporting Universal Links in Your App](https://developer.apple.com/documentation/xcode/supporting-universal-links-in-your-app?language=objc).

## Testing and troubleshooting

### Test URL grammar

Your route enum is pure data logic, so it can be tested without launching the app:

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

### Test a Universal Link on a device

1. Verify that `https://example.com/.well-known/apple-app-site-association` is reachable.
2. Delete and reinstall the app.
3. Paste the complete URL into Notes or Messages, then tap or long-press it.
4. Do not only type the URL in Safari’s address bar; that is normally treated as browser navigation.

Apple’s [TN3155: Debugging Universal Links](https://developer.apple.com/documentation/technotes/tn3155-debugging-universal-links/) has additional device diagnostics.

### Common problems

| Symptom | Check |
| --- | --- |
| Link opens Safari | Check Associated Domains, AASA `appIDs`, HTTPS, redirects, then reinstall the app. |
| `.onOpenURL` runs but no page changes | Check `allowedHosts`, `pathComponents`, and errors from `AppRoute.presentation(for:)`. |
| A detail page appears twice | Do not create separate `NavigationStack` instances in both a feature view and `RouterHost`. |
| Wrong tab is selected | Use `Optional(AppRoute.someTab)` as the `.tag`. |
| A background-task navigation fails | Update the router inside `await MainActor.run { router.apply(...) }`. |

## License

URLRouter is released under the [MIT License](LICENSE). You may use, copy, modify, distribute, and use it in commercial projects. Preserve the copyright and license notices when distributing the software or substantial portions of it. See [LICENSE](LICENSE) for the full terms.
