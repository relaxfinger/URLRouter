# URLRouter

[🇨🇳 中文](README.zh-CN.md) · [Documentation](docs/README.md) · [Blog tutorial](https://zhangjipeng.com/post-urlrouter.html)

> A SwiftUI routing foundation for modular Apple-platform apps.
>
> iOS 17+ · macOS 14+ · tvOS 17+ · watchOS 10+ · Swift 6

URLRouter gives an app one predictable front door for navigation. A button, a
push notification, a Universal Link, or another Feature can all submit the
same HTTPS URL. URLRouter validates it, lets the owning Feature resolve it, and
updates SwiftUI navigation in the presentation style declared by the URL.

It is useful once an app has more than a few screens: callers no longer need to
know another Feature's View type, initializer, or navigation container. They
only use that Feature's documented URL contract.

## Choose your path

| If you want to… | Start here |
| --- | --- |
| Open one page from a SwiftUI button | [Five-minute quick start](docs/getting-started.md#five-minute-quick-start) |
| Add Universal Links and a modular Feature Package | [Getting started guide](docs/getting-started.md) |
| Understand ownership and URL contracts | [Architecture guide](docs/architecture.md) |
| Add remote switches, queueing, telemetry, or CI checks | [Production governance](docs/production-governance.md) |
| Follow a complete beginner-friendly walkthrough | [Technical blog](https://zhangjipeng.com/post-urlrouter.html) |

The README is deliberately short. The linked guides contain the rationale,
production details, and Chinese counterparts without forcing every app to adopt
advanced features on day one.

## Install

In Xcode, choose **File → Add Package Dependencies…** and add:

```text
https://github.com/relaxfinger/URLRouter.git
```

Add `URLRouter` to the App target and to any Feature Package that declares a
`RouteModule`.

```swift
dependencies: [
    .package(url: "https://github.com/relaxfinger/URLRouter.git", from: "2.5.4")
]
```

`URLRouterPolicyProvider` is an optional product from the same package. Add it
only when the App needs a cache-first remote route-policy lifecycle. Feature
packages should normally depend on `URLRouter` only.

```swift
.product(name: "URLRouter", package: "URLRouter")
// App-shell target only, when remote policy is needed:
.product(name: "URLRouterPolicyProvider", package: "URLRouter")
```

## Five-minute quick start

### 1. Let a Feature own its paths and destination views

```swift
import SwiftUI
import URLRouter

enum ArticleFeature {
    static let module = RouteModule(
        id: "articles",
        resolve: { link in
            guard case ["articles", let id] = link.pathComponents, !id.isEmpty else {
                return nil
            }
            return ModuleRoute(
                moduleID: "articles",
                routeID: "detail",
                parameters: ["id": id]
            )
        },
        destination: { route in
            guard route.routeID == "detail", let id = route.parameters["id"] else {
                return nil
            }
            return AnyView(ArticleDetailView(articleID: id))
        }
    )
}
```

Returning `nil` from `resolve` means “this URL is not mine.” A Feature can own
many URLs; keep their parsing and destination creation together.

### 2. Register Feature modules once at the scene root

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
                ContentView()
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

Install `RouterHost` and `moduleLinkRouting` exactly once per scene. Keep one
`ModuleRouter` per window so multi-window navigation stays independent.

### 3. Navigate with the standard SwiftUI API

```swift
struct ArticleRow: View {
    @Environment(\.openURL) private var openURL
    let articleID: String

    var body: some View {
        Button("Read article") {
            openURL(URL(string: "https://example.com/articles/\(articleID)?presentation=push&version=1")!)
        }
    }
}
```

The URL is the public contract:

```text
https://example.com/articles/42?presentation=push&version=1
```

`presentation` is required and may be `push`, `tab`, `sheet`, or
`fullScreenCover`. Start with one route like this. Then follow the
[getting-started guide](docs/getting-started.md) to use URL builders,
Universal Links, tabs, and a versioned route contract safely.

## When to add the optional production features

Do not build every feature at once.

| Need | Add |
| --- | --- |
| Web links should open the same route as the app | Universal Links |
| A Feature or all routing must be remotely paused | `URLRouterPolicyProvider` and a `ModuleRoutePolicyStore` |
| A notification, link, and button can arrive together | One `ModuleRouteCoordinator` per scene |
| Support needs to explain why a link failed | `ModuleRouteObservability` |
| Marketing or web clients depend on published links | `RouteContracts.json` and contract CI |

These are opt-in. URLRouter does not choose your network client, authentication
flow, remote-config vendor, analytics vendor, or backend. The App owns those
decisions; the package provides focused routing seams.

## Demo and verification

`URLRouterDemo` is an iOS 17+ reference app. It shows local Feature Packages,
all four presentation styles, cross-package navigation, a cache-first policy
lifecycle, telemetry, and coordinated concurrent routes.

```bash
swift test
swift Scripts/update_route_contracts.swift
swift Scripts/validate_route_contract.swift RouteContracts.json
```

`update_route_contracts.swift` scans every Feature Swift Package and the
App-owned Swift sources for `RouteModule` declarations, then creates or updates
the single App-owned `RouteContracts.json`. Feature Packages do not keep their
own copies. The generator fails when it cannot reliably infer a route, rather
than publishing a guessed contract. The catalog places App-owned routes in an
`App` section and keeps each Feature Package in its own section.

When URLRouter lives outside the App repository, point the script at the App
root (all relative paths below are resolved from it):

```bash
swift /path/to/URLRouter/Scripts/update_route_contracts.swift \
  --app-root /path/to/MyApp \
  --output RouteContracts.json
swift /path/to/URLRouter/Scripts/generate_route_catalog.swift \
  --app-root /path/to/MyApp \
  --contracts RouteContracts.json \
  --output docs/route-catalog.html
```

The generated catalog is searchable and splits routes into one table per
Feature package. Its top navigator shows each Feature and its route count for
quick browsing.

### Automate remote SPM dependencies

URLRouter ships two Plugin Products, so an App never needs to record a remote
checkout path. After adding URLRouter as a remote dependency, enable
`URLRouterRouteBuildPlugin` in the target’s **Build Phases → Run Build Tool
Plug-ins**. Every build validates the route contract and creates a browsable
catalog in the plugin work directory under Derived Data; it never changes the
App repository.

After adding or changing routes, select **File → Packages →
URLRouterRouteCommandPlugin** in Xcode, or run this from a Swift Package App
root:

```bash
swift package plugin generate-urlrouter-contracts --allow-writing-to-package-directory
```

The command explicitly requests write access and then updates the App-root
`RouteContracts.json` and `docs/route-catalog.html` for review and commit. The
catalog script creates a missing initial contract automatically; a sandboxed
SwiftPM Build Plugin remains validation-only.

For the full, step-by-step Xcode setup (including how to add the Build Plugin,
run the Command Plugin, review its output, and fix a missing plugin in the
picker), see [Route-plugin workflow](docs/route-plugin-workflow.md).

The core library and `RouterHost` support all four listed Apple platforms. On
macOS, SwiftUI presents a `fullScreenCover` route as a sheet because macOS does
not provide `fullScreenCover`.

## Project layout

```text
Sources/URLRouter/                 # core routing library
Sources/URLRouterPolicyProvider/   # optional policy-refresh product
Tests/                             # SwiftPM unit tests
Features/                          # local Feature-package examples
URLRouterDemo/                     # executable iOS reference app
docs/                              # task-focused documentation
```

## License and community

URLRouter is available under the [MIT License](LICENSE). Before contributing,
read [CONTRIBUTING.md](CONTRIBUTING.md). For support, security reports, and the
maintenance policy, see [SUPPORT.md](SUPPORT.md), [SECURITY.md](SECURITY.md),
and [MAINTENANCE.md](MAINTENANCE.md).
