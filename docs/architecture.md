# URLRouter architecture and route contracts

[中文](architecture.zh-CN.md) · [Documentation index](README.md)

This guide explains the boundaries that keep a routing setup understandable as
the number of screens and Feature packages grows.

## The four responsibilities

| Part | Owns |
| --- | --- |
| URL contract | A stable, public address for a destination and its presentation style |
| Feature Package | URL parsing plus creation of the destination view |
| App shell | Linked module registration, trusted hosts, policy, and scene navigation state |
| URLRouter | URL validation, route resolution, and SwiftUI navigation state changes |

An optional fifth piece, `URLRouterPolicyProvider`, refreshes a remote policy
into an in-memory policy store. It never performs navigation and the core
library does not depend on it.

## Recommended package direction

```text
App target
  ├── ArticleFeature package ──> URLRouter
  ├── SettingsFeature package ─> URLRouter
  └── URLRouterPolicyProvider (optional, App target only)
```

Features do not import each other to present views. The App depends on Feature
packages and registers their public `RouteModule`s. A Feature may expose a
small URL-builder API, or a shared contracts package may expose builders when a
strict dependency graph requires it. Do not expose another Feature's view type
as a navigation API.

## Design URLs as public contracts

Use URLs that a web page, notification, and another Feature can all understand:

```text
https://example.com/articles/42?presentation=push&version=1
```

Keep these rules from the first release:

- HTTPS only, with hosts controlled by your team.
- Stable IDs only; never credentials, tokens, contact data, or full JSON.
- `presentation` is required: `push`, `tab`, `sheet`, or `fullScreenCover`.
- Public or long-lived links include a contract `version`.
- The owning Feature documents and constructs its own URLs with `URLComponents`.

A published URL has the same compatibility cost as a public Swift API. Prefer
adding a new path or version during a migration; do not quietly reinterpret or
delete an existing path.

## Keep parsing local to the Feature

One module can own several links. Put literal paths before parameterized paths:

```swift
switch link.pathComponents {
case ["articles"]:
    return ModuleRoute(moduleID: "articles", routeID: "list")
case ["articles", "saved"]:
    return ModuleRoute(moduleID: "articles", routeID: "saved")
case ["articles", let id] where !id.isEmpty:
    return ModuleRoute(moduleID: "articles", routeID: "detail", parameters: ["id": id])
default:
    return nil
}
```

Do not accept path suffixes that the contract does not define. A strict parser
makes a malformed external link fail safely instead of opening a surprising
screen.

`ModuleRoute` contains a module ID, route ID, and string parameters. Keep
business objects out of it; the destination can load fresh data through its
view model or use case. That makes restoration, testing, and cross-package
boundaries simpler.

## Keep the App shell small

`AppRoutes.swift` should only register modules already linked into the app:

```swift
enum AppRoutes {
    static let registry = ModuleRouteRegistry(modules: [
        ArticleFeature.module,
        SettingsFeature.module
    ])
}
```

It should not become one giant switch over every path. The registry validates
duplicate module IDs, incorrect module ownership, and missing destinations for
presented routes.

The shell is the appropriate place for global rules: trusted hosts, supported
URL versions, feature flags, authorization decisions, and analytics adapters.
It is not the right place to hard-code an app's login implementation. Let the
app decide how to authenticate; let the routing policy say whether the current
route may open.

## Use tabs deliberately

`RouterHost` manages pushed and modal destinations. For tab routes it writes
`router.selectedTab`. Bind that state to the root `TabView` selection, and use
the same identifier for the URL route ID and the tab tag. This keeps a tab URL
from being “handled” without visibly switching tabs.

## Publishing or changing a route

For every public route change, update these items in one pull request:

1. The Feature's parser and URL builder.
2. `RouteContracts.json`.
3. Tests and caller documentation.
4. Migration notes if an old URL remains in emails, websites, notifications, or
   released apps.

The repository CI catches structural and breaking catalog changes; it cannot
decide your product migration policy. Treat a removed or reinterpreted URL as a
breaking change and plan it accordingly.

For rollout, remote policy, concurrency, and observability guidance, continue
to [Production governance](production-governance.md).
