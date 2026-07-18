# URLRouter

[🇨🇳 中文](README.zh-CN.md)

> iOS 17+ · macOS 14+ · tvOS 17+ · watchOS 10+ · Swift 6 · SwiftUI · modular `openURL` routing

URLRouter is a SwiftUI routing foundation for modular apps. Feature code always navigates with `openURL`; URLRouter validates the URL, finds the owning Feature Package, and applies the presentation encoded in the URL.

## Contents

1. [Install](#install)
2. [Architecture](#architecture)
3. [Universal Link setup](#universal-link-setup)
4. [Feature Package](#feature-package)
5. [App Shell](#app-shell)
6. [Production governance](#production-governance)
7. [Routing scenarios](#routing-scenarios)
8. [Demo and testing](#demo-and-testing)

## Install

Add `https://github.com/relaxfinger/URLRouter.git` in **File > Add Package Dependencies…**, then import `URLRouter`. The minimum deployment target is iOS 17, macOS 14, tvOS 17, or watchOS 10.

### Compatibility

- Apple 2023 platform generation: iOS 17+, macOS 14+, tvOS 17+, and watchOS 10+
- Swift 6 language mode
- Xcode 16 or later

### Package layout

The repository follows the standard Swift Package Manager layout. The library
and its tests can be built directly with SwiftPM; the Xcode project remains
only as an executable demo host.

```text
Sources/URLRouter/        # public library source
Tests/URLRouterTests/     # unit tests
Features/                 # local feature-package examples
URLRouterDemo/            # SwiftUI demo app
```

## Architecture

URLRouter lets Feature views navigate with one API: `openURL`. Register each Feature Package once in the App Shell, then use a complete HTTPS URL with a required `presentation` query item. Valid values are `push`, `tab`, `sheet`, and `fullScreenCover`. Production app shells can additionally enforce a versioned URL contract with `ModuleRoutePolicy`, remotely restrict routes with `ModuleRoutePolicyStore`, and emit vendor-neutral telemetry through `ModuleRouteObservability`.

```text
https://example.com/articles/42?presentation=push&version=1
https://example.com/favorites?presentation=tab&version=1
https://example.com/settings?presentation=sheet&version=1
https://example.com/sign-in?presentation=fullScreenCover&version=1
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
            switch link.pathComponents {
            case ["articles", let articleID]:
                return ModuleRoute(
                    moduleID: id,
                    routeID: "detail",
                    parameters: ["id": articleID]
                )
            case ["articles", let articleID, "comments"]:
                return ModuleRoute(
                    moduleID: id,
                    routeID: "comments",
                    parameters: ["id": articleID]
                )
            case ["articles", "search"]:
                return ModuleRoute(moduleID: id, routeID: "search")
            default:
                return nil
            }
        },
        destination: { route in
            switch route.routeID {
            case "detail":
                return AnyView(ArticleView(id: route.parameters["id"] ?? ""))
            case "comments":
                return AnyView(CommentsView(articleID: route.parameters["id"] ?? ""))
            case "search":
                return AnyView(ArticleSearchView())
            default:
                return nil
            }
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
            openURL(URL(string: "https://example.com/articles/42?presentation=push&version=1")!)
        }
    }
}
```

One `RouteModule` can therefore own multiple links. In this example, the Feature owns the following public URL contracts:

```text
https://example.com/articles/42?presentation=push&version=1
https://example.com/articles/42/comments?presentation=sheet&version=1
https://example.com/articles/search?presentation=tab&version=1
```

The path selects the `routeID` and parameters; `presentation` selects how SwiftUI displays the resolved destination.

## App Shell

The app links Feature Packages and registers them once. It never parses feature paths or chooses push/tab/sheet/full-screen presentation.

```swift
@main
struct MyApp: App {
    @State private var router = ModuleRouter()
    private let routePolicy = ModuleRoutePolicy(
        acceptedContractVersions: ["1"],
        allowsUnversionedLinks: false
    )
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
                allowedHosts: ["example.com"],
                policy: routePolicy,
                onFailure: { url, error in
                    print("Discarded route \(url.absoluteString): \(error.localizedDescription)")
                },
                onEvent: { event in
                    print("Route trace \(event.traceID): \(event.outcome.rawValue)")
                }
            )
        }
    }
}
```

Swift cannot discover unlinked packages at runtime. With two or more Feature Packages, the App Shell adds each package's single `RouteModule` to this one registry. Adding a feature requires linking its package and adding that module, but never editing a central URL `switch`, path parser, or presentation mapping.

The registry rejects duplicate module IDs, a route returned by the wrong module, and push/sheet/full-screen routes without a destination. `ModuleRoutePolicy` lets the App Shell enforce contract versions, feature flags, authorization, and permitted presentation styles without coupling Feature Packages to those systems. Use `onFailure` to log rejected URLs and `onEvent` for privacy-conscious telemetry: each event includes a trace ID, outcome, route metadata, and no query values. A router has one active modal route: a new modal replaces the previous one, while push and tab routes dismiss the active modal before navigating. Repeated pushes of the same route are idempotent.

## Production governance

### Remote policy and emergency circuit breaker

`ModuleRouteRemotePolicy` is a Codable restriction document that the App Shell can fetch from any approved remote-config service. The library never fetches configuration itself: the host must authenticate, validate, cache, and roll back the document. A remote policy can only restrict a local policy; it cannot grant authorization.

```swift
@State private var routePolicyStore = ModuleRoutePolicyStore(
    localPolicy: ModuleRoutePolicy(
        acceptedContractVersions: ["1"],
        allowsUnversionedLinks: false
    )
)

func applyTrustedRemotePolicy(_ data: Data) throws {
    let remotePolicy = try JSONDecoder().decode(ModuleRouteRemotePolicy.self, from: data)
    routePolicyStore.replaceRemotePolicy(with: remotePolicy)
}
```

Set `isCircuitBreakerOpen` to `true` for an immediate, release-free stop to module routing. The same document can disable individual modules, provide an allow-list, reject presentation styles, or tighten accepted contract versions.

### Unified observability

Adopt `ModuleRouteObserving` in adapters for your logging, metrics, and tracing SDKs, then supply a `ModuleRouteObservability` instance to `moduleLinkRouting`. Each event carries a trace ID, outcome, host, module/route identity, presentation, and a stable `failureCode`; it deliberately excludes URL query values.

### Route contract CI

[`RouteContracts.json`](RouteContracts.json) is the source-controlled public route catalog. CI runs `Scripts/validate_route_contract.swift` before builds and rejects duplicate route IDs or path/presentation invocations, invalid presentation values, and contracts that omit required `presentation` or `version` parameters. Update the catalog, feature parser, release notes, and migration plan together whenever a public route changes.

## Routing scenarios

| Intent | Feature code |
| --- | --- |
| Push detail | `openURL(URL(string: "https://example.com/articles/42?presentation=push&version=1")!)` |
| Select tab | `openURL(URL(string: "https://example.com/favorites?presentation=tab&version=1")!)` |
| Show sheet | `openURL(URL(string: "https://example.com/settings?presentation=sheet&version=1")!)` |
| Full-screen flow | `openURL(URL(string: "https://example.com/sign-in?presentation=fullScreenCover&version=1")!)` |

After asynchronous work, return to the main actor before calling `openURL`:

```swift
Task {
    let id = try await articleService.recommendedArticleID()
    await MainActor.run {
        openURL(URL(string: "https://example.com/articles/\(id)?presentation=push&version=1")!)
    }
}
```

### Navigate from one Feature Package to another

Feature A does not import Feature B or reference its views. It emits Feature B's documented URL contract:

```swift
// Inside NavigationFeature
@Environment(\.openURL) private var openURL

Button("Open content article") {
    openURL(URL(string: "https://example.com/articles/42?presentation=push&version=1")!)
}
```

`ContentFeature` owns `/articles/*` and supplies `ArticleView`. It can route back to `NavigationFeature` the same way:

```swift
// Inside ContentFeature
Button("Open settings") {
    openURL(URL(string: "https://example.com/settings?presentation=sheet&version=1")!)
}
```

Both modules must be linked and included in `ModuleRouteRegistry`. The demo registers `DemoNavigationFeature` and `DemoContentFeature`, and demonstrates both directions.

## Demo and testing

The demo uses two real local Swift Packages:

```text
Features/
├── NavigationFeature/  # home, favorites, settings, sign-in
└── ContentFeature/     # article details
```

Both Packages depend on `URLRouter`, but they do not depend on each other. `NavigationFeature` opens article URLs owned by `ContentFeature`; `ContentFeature` opens settings URLs owned by `NavigationFeature`.

This boundary is intentional: use URL contracts for cross-feature navigation rather than importing another Feature Package merely to access its views or route types.

`URLRouterDemo` is an iOS 17+ reference app that demonstrates the platform-neutral `RouterHost` composition, all four URL presentation styles, cross-package navigation, strict version-1 contract enforcement, an in-app route telemetry status, and the remote-policy emergency routing switch. The same `RouterHost`, `moduleLinkRouting`, and Feature Packages are available to apps targeting macOS 14+, tvOS 17+, or watchOS 10+; SwiftUI adapts their navigation and modal presentation to each platform. Because SwiftUI does not provide `fullScreenCover` on macOS, that presentation is rendered as a sheet there.

Open `URLRouter.xcodeproj`, choose the **URLRouterDemo** scheme, select an iOS 17+ simulator, and run it. Xcode resolves both local packages automatically.

Run tests with:

```bash
swift test
swift Scripts/validate_route_contract.swift RouteContracts.json
```

## License

URLRouter is released under the [MIT License](LICENSE).
