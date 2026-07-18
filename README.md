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
Sources/URLRouterPolicyProvider/  # optional cache-first policy refresh module
Tests/URLRouterTests/     # unit tests
Tests/URLRouterPolicyProviderTests/ # provider unit tests
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

In plain terms, a remote policy is a route control panel that the backend can change without waiting for an App Store release. If the article module has an incident, the backend can disable `content`; the next article link is safely rejected. If routing itself is unsafe, setting `isCircuitBreakerOpen` to `true` pulls the main switch: all module routes stop immediately while the rest of the app continues to work.

The backend sends ordinary JSON such as:

```json
{
  "isCircuitBreakerOpen": false,
  "disabledModuleIDs": ["content"],
  "allowedPresentationStyles": ["push", "tab"],
  "acceptedContractVersions": ["1"]
}
```

`ModuleRouteRemotePolicy` represents this JSON in Swift. URLRouter never fetches configuration itself: the host app fetches it from a company service, Firebase, or another configuration service and owns authentication, signature verification, caching, and rollback. A remote policy can only **tighten** local rules; it cannot bypass local authorization or re-enable a locally rejected contract version.

For the recommended cache-first app lifecycle, add the optional product from this same package:

```swift
.product(name: "URLRouterPolicyProvider", package: "URLRouter")
```

`URLRouterPolicyProvider` depends on `URLRouter`; the reverse is not true. It
does not choose an HTTP client, remote-config vendor, or signing scheme. The
app supplies only where data comes from and how it is verified; the provider
handles this failure-prone lifecycle:

```text
App starts
  → restore the last verified local cache immediately
  → fetch the newest policy in the background without blocking the first screen
  → validate and atomically replace the active policy
  → save the new verified cache
  → keep the old cache after a temporary failure; fall back to local safe rules when it is too old
```

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

To use it, the app gives a `ModuleRoutePolicyStore` to `moduleLinkRouting`, then calls `replaceRemotePolicy` only after receiving and validating a new policy. The next route automatically uses the new rules; no view rebuild or app release is needed. Set `isCircuitBreakerOpen` to `true` for an immediate stop to module routing. The same document can disable individual modules, provide an allow-list, reject presentation styles, or tighten accepted contract versions.

### Recommended app refresh strategy

Do not fetch the backend for every link: that is slow and unreliable. Use this sequence instead: read the last verified cache first, refresh in the background at cold start, refresh when the app becomes active after the TTL, and keep the last verified policy during a temporary outage. If no verified cache exists or it exceeds the hard stale limit, URLRouter keeps the app's local safe policy. The defaults are a 30-minute foreground refresh, one-hour normal cache, and a 24-hour hard stale limit. Use a shorter TTL or push-triggered refresh for incident-sensitive circuit breakers.

```swift
import URLRouter
import URLRouterPolicyProvider

struct CompanyPolicySource: RoutePolicyRemoteSource {
    func fetchPolicyData() async throws -> Data {
        let url = URL(string: "https://config.example.com/mobile/route-policy")!
        let (data, response) = try await URLSession.shared.data(from: url)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else {
            throw URLError(.badServerResponse)
        }
        return data
    }
}

@MainActor
final class AppRoutePolicySession {
    let store = ModuleRoutePolicyStore(localPolicy: ModuleRoutePolicy(
        acceptedContractVersions: ["1"],
        allowsUnversionedLinks: false
    ))
    let provider: RoutePolicyProvider

    init(cacheURL: URL) {
        provider = RoutePolicyProvider(
            store: store,
            source: CompanyPolicySource(),
            cache: FileRoutePolicyCache(url: cacheURL),
            strategy: .standard // 30 min refresh, 1 h normal cache, 24 h hard stale limit
        )
    }

    func start() async {
        _ = await provider.bootstrap() // use verified disk cache; never waits for network
        _ = await provider.refresh()   // fetch the newest policy in the background
    }

    func appBecameActive() async {
        _ = await provider.refreshIfNeeded()
    }
}
```

Use `JSONRoutePolicyPayloadValidator` for a plain trusted JSON endpoint. For a
signed response or envelope, implement `RoutePolicyPayloadValidating`; only a
validated `ModuleRouteRemotePolicy` is cached or applied. A corrupted response
or intercepted network payload therefore cannot replace the current working
policy with a partial value.

### Unified observability

In plain terms, unified observability is a dashcam for routing. When a user says “the order link did nothing,” the team can see whether the route succeeded, was circuit-broken, used an unsupported version, targeted a disabled module, or was malformed. It also lets monitoring alert when one failure reason suddenly spikes.

To use it, write a small adapter that forwards an event to the logging, metrics, or tracing systems your company already uses, then pass it to `moduleLinkRouting`. `ModuleRouteObservability` can fan each event out to multiple observers: for example, one logs and one increments a metric.

```swift
@MainActor
final class AppRouteObserver: ModuleRouteObserving {
    func record(_ event: ModuleRouteEvent) {
        logger.notice("route outcome=\(event.outcome.rawValue) trace=\(event.traceID)")
        metrics.increment("route.\(event.failureCode ?? "handled")")
    }
}

let observability = ModuleRouteObservability(observers: [AppRouteObserver()])
```

Each event carries a trace ID, outcome, host, module/route identity, presentation, and a stable `failureCode`. It deliberately excludes URL query values, tokens, phone numbers, and other potentially sensitive data. Use the trace ID to correlate with your app's controlled logs when troubleshooting.

### Route contract CI

In plain terms, route contract CI treats a URL as an interface agreement between teams. `/articles/:id?presentation=push&version=1` is not just a string: another Feature, a web page, a push notification, or an older app may depend on it. Without this check, one team can change a path or presentation and another team discovers broken links only in production.

[`RouteContracts.json`](RouteContracts.json) is the source-controlled public route catalog. Every entry states who owns a route, its path shape, permitted presentation styles, and required parameters. CI runs `Scripts/validate_route_contract.swift` before builds and rejects duplicate route IDs or path/presentation invocations, invalid presentation values, and contracts that omit required `presentation` or `version` parameters.

To use it, update four things in the same PR whenever a public link changes: the Feature URL parser, `RouteContracts.json`, the README/caller examples, and any required migration notes. CI catches structural catalog mistakes; whether an old URL can be removed and how old clients migrate must still be explicit in PR review and release notes. That distinction prevents “automatic validation” from being mistaken for “automatic compatibility.”

In addition, PR CI compares the catalog with the exact base commit. It rejects a removed route, changed path template, removed presentation style, removed required parameter, or removed supported contract version. This makes a public-link breaking change visible before merge; make such a change only in a major release with a migration plan.

### Public API compatibility CI

In plain terms, this is the same safety net for Swift code that route-contract CI is for URLs. An app may import `URLRouter` or `URLRouterPolicyProvider` and call a public type or method for years. Removing or changing that API without a major-version migration breaks the app at its next dependency update.

For every pull request, CI uses SwiftPM's API comparison tool to compare both public library products with the exact base commit of the PR. It rejects removed public types, changed signatures, and other source-compatible breaks before the PR can merge. Additive APIs are allowed. Intentionally breaking an API requires a major release and an explicit migration guide; do not silence the check merely to merge a minor or patch release.

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

`URLRouterDemo` is an iOS 17+ reference app that demonstrates the platform-neutral `RouterHost` composition, all four URL presentation styles, cross-package navigation, strict version-1 contract enforcement, an in-app route telemetry status, and the optional `URLRouterPolicyProvider` cache-first refresh lifecycle. Its `DemoPolicySource` is intentionally local; replace it with an App-owned source in production. The same `RouterHost`, `moduleLinkRouting`, and Feature Packages are available to apps targeting macOS 14+, tvOS 17+, or watchOS 10+; SwiftUI adapts their navigation and modal presentation to each platform. Because SwiftUI does not provide `fullScreenCover` on macOS, that presentation is rendered as a sheet there.

Open `URLRouter.xcodeproj`, choose the **URLRouterDemo** scheme, select an iOS 17+ simulator, and run it. Xcode resolves both local packages automatically.

Run tests with:

```bash
swift test
swift Scripts/validate_route_contract.swift RouteContracts.json
```

## License

URLRouter is released under the [MIT License](LICENSE).
