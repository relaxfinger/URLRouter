# Getting started with URLRouter

[中文](getting-started.zh-CN.md) · [Documentation index](README.md)

This guide gets one production-shaped route running before you introduce any
remote configuration or queueing. The goal is simple: a button and a Universal
Link should open the same SwiftUI destination through one public URL.

## Before you begin

- Deploy to iOS 17+, macOS 14+, tvOS 17+, or watchOS 10+.
- Choose an HTTPS domain your team controls, such as `example.com` below.
- Add `URLRouter` to the App target and every Feature Package that declares a
  `RouteModule`.

Do not add `URLRouterPolicyProvider` yet. It is optional and belongs in the App
shell only when you need remotely managed restrictions.

## 1. Define one stable URL contract

Start with a complete URL, not an internal View name:

```text
https://example.com/articles/42?presentation=push&version=1
```

- `/articles/42` identifies the destination.
- `presentation=push` tells SwiftUI how to show it.
- `version=1` lets a future app support a new URL shape without guessing.

Use HTTPS and a trusted host. Put stable IDs in URLs, never tokens, passwords,
phone numbers, or an entire JSON object. Once a link appears in a web page,
email, or notification, treat it as a public API.

Build URLs with `URLComponents` in the owning Feature rather than copying
strings around the app:

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

## 2. Make the owning Feature resolve it

The Feature owns both its URL grammar and its destination views. A resolver
returns `nil` when a URL belongs to another Feature.

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

Put fixed paths such as `/articles/saved` before the general
`/articles/:id` case. Otherwise `saved` would be mistaken for an article ID.

## 3. Assemble modules in the App shell

The App shell is the only place that knows which Feature packages are linked.
It registers modules, creates navigation state, and applies app-wide rules. It
does not parse Feature paths or construct Feature views.

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

Install `RouterHost` and `moduleLinkRouting` once per scene. Each window should
have its own `ModuleRouter`; that keeps multi-window state isolated.

## 4. Navigate from ordinary SwiftUI code

`moduleLinkRouting` supplies SwiftUI's standard `openURL` action. Child views
do not need a router reference:

```swift
struct ArticleRow: View {
    let id: String
    @Environment(\.openURL) private var openURL

    var body: some View {
        Button("Read") {
            openURL(ArticleLinks.detail(id: id))
        }
    }
}
```

After asynchronous work, return to the main actor before calling it:

```swift
Task {
    let id = try await recommendationService.nextArticleID()
    await MainActor.run {
        openURL(ArticleLinks.detail(id: id))
    }
}
```

## 5. Make tab routes change your TabView

For a `presentation=tab` route, URLRouter updates `router.selectedTab`. Bind
your `TabView` selection to that value. Keep the tab `routeID` and the SwiftUI
tag equal, for example `favorites`.

```swift
struct AppTabs: View {
    @Bindable var router: ModuleRouter

    var body: some View {
        TabView(selection: Binding(
            get: { router.selectedTab?.routeID ?? "home" },
            set: { router.selectedTab = ModuleRoute(moduleID: "navigation", routeID: $0) }
        )) {
            HomeView().tabItem { Label("Home", systemImage: "house") }.tag("home")
            FavoritesView().tabItem { Label("Favorites", systemImage: "star") }.tag("favorites")
        }
    }
}
```

## 6. Add Universal Links

1. Add the **Associated Domains** capability to the App target.
2. Add `applinks:example.com`.
3. Serve `https://example.com/.well-known/apple-app-site-association` over
   HTTPS without redirects.
4. Declare only paths that the app actually supports.

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

Test on a physical device. A valid domain association is an Apple platform
requirement; it is separate from URLRouter's own URL validation.

## Next steps

- Read [Architecture](architecture.md) before publishing routes for multiple
  teams or packages.
- Read [Production governance](production-governance.md) when product needs
  remote route restrictions, incident controls, telemetry, or concurrent-route
  handling.
