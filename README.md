# URLRouter

[🇨🇳 中文](README.zh-CN.md)

> iOS 17+ · Swift 6 · SwiftUI · Universal Links · modular `openURL` routing

URLRouter is a SwiftUI routing foundation for modular apps. Feature code always navigates with `openURL`; URLRouter validates the URL, finds the owning Feature Package, and applies the presentation encoded in the URL.

## Contents

1. [Install](#install)
2. [Architecture](#architecture)
3. [Universal Link setup](#universal-link-setup)
4. [Feature Package](#feature-package)
5. [App Shell](#app-shell)
6. [Routing scenarios](#routing-scenarios)
7. [Demo and testing](#demo-and-testing)

## Install

Add `https://github.com/relaxfinger/URLRouter.git` in **File > Add Package Dependencies…**, then import `URLRouter`. The minimum deployment target is iOS 17.

## Architecture

URLRouter lets Feature views navigate with one API: `openURL`. Register each Feature Package once in the App Shell, then use a complete HTTPS URL with a required `presentation` query item. Valid values are `push`, `tab`, `sheet`, and `fullScreenCover`.

```text
https://example.com/articles/42?presentation=push
https://example.com/favorites?presentation=tab
https://example.com/settings?presentation=sheet
https://example.com/sign-in?presentation=fullScreenCover
```


## Universal Link setup

1. Add the **Associated Domains** capability and `applinks:example.com`.
2. Host `https://example.com/.well-known/apple-app-site-association` over HTTPS without redirects.
3. Install `moduleLinkRouting` once at the `WindowGroup` root.

Example AASA configuration (replace the team and bundle IDs):

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

A Feature Package registers its own URL grammar and destination factory. This is the only layer that knows its paths and views.

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

Ordinary Feature views only use SwiftUI:

```swift
struct ArticleList: View {
    @Environment(\.openURL) private var openURL

    var body: some View {
        Button("Open article 42") {
            openURL(URL(string: "https://example.com/articles/42?presentation=push")!)
        }
    }
}
```

## App Shell

The app links Feature Packages and registers them once. It never parses feature paths or chooses push/tab/sheet/full-screen presentation.

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

Swift cannot discover unlinked packages at runtime. With two or more Feature Packages, the App Shell adds each package's single `RouteModule` to this one registry. Adding a feature requires linking its package and adding that module, but never editing a central URL `switch`, path parser, or presentation mapping.

## Routing scenarios

| Intent | Feature code |
| --- | --- |
| Push detail | `openURL(URL(string: "https://example.com/articles/42?presentation=push")!)` |
| Select tab | `openURL(URL(string: "https://example.com/favorites?presentation=tab")!)` |
| Show sheet | `openURL(URL(string: "https://example.com/settings?presentation=sheet")!)` |
| Full-screen flow | `openURL(URL(string: "https://example.com/sign-in?presentation=fullScreenCover")!)` |

After asynchronous work, return to the main actor before calling `openURL`:

```swift
Task {
    let id = try await articleService.recommendedArticleID()
    await MainActor.run {
        openURL(URL(string: "https://example.com/articles/\(id)?presentation=push")!)
    }
}
```

## Demo and testing

Open `URLRouter.xcodeproj`, choose the **URLRouterDemo** scheme, select an iOS 17+ simulator, and run it. The demo shows all four URL presentation styles and direct URL simulation.

Run tests with:

```bash
swift test
```

## License

URLRouter is released under the [MIT License](LICENSE).
