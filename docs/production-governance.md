# Production route governance

[中文](production-governance.zh-CN.md) · [Documentation index](README.md)

Start with the direct routing modifier. Add the capabilities below only when a
real product requirement appears. They do not bind your app to a backend,
authentication SDK, analytics service, or remote-config vendor.

## Remote policy and circuit breaking

A remote policy is a small route control panel. It is useful when an App Store
release would be too slow: disable a broken checkout Feature, restrict a
presentation style, or stop module routes during a serious incident. The backend
does not decide navigation; it supplies restrictions that the app applies
locally.

`ModuleRoutePolicy` is the app's non-negotiable local baseline. Remote policy
can only tighten it; it cannot bypass local authorization or re-enable an
unsupported URL version.

```swift
let localPolicy = ModuleRoutePolicy(
    acceptedContractVersions: ["1"],
    allowsUnversionedLinks: false,
    isModuleEnabled: { featureFlags.isEnabled($0) },
    isAuthorized: { route, _ in
        permissions.canOpen(moduleID: route.moduleID, routeID: route.routeID)
    }
)
```

For example, a protected HTTPS endpoint can return:

```json
{
  "isCircuitBreakerOpen": false,
  "disabledModuleIDs": ["checkout"],
  "allowedPresentationStyles": ["push", "tab"],
  "acceptedContractVersions": ["1"]
}
```

The App owns authentication and, for high-impact controls, signature
verification before applying the payload.

## Optional Provider: cache first, refresh in the background

`URLRouterPolicyProvider` is not a backend call before every navigation. It
maintains a `ModuleRoutePolicyStore` separately, while each route reads that
in-memory store synchronously.

```text
Cold start:       restore the last verified cache immediately
After first view: fetch the latest policy in the background
App active:       refresh only after the configured interval
Fetch fails:      keep the last verified policy
Cache too old:    fall back to the app's local safe policy
```

Only the App shell imports the optional product:

```swift
import URLRouter
import URLRouterPolicyProvider

@MainActor
final class AppRoutePolicySession {
    let store: ModuleRoutePolicyStore
    let provider: RoutePolicyProvider

    init(localPolicy: ModuleRoutePolicy, cacheURL: URL) {
        store = ModuleRoutePolicyStore(localPolicy: localPolicy)
        provider = RoutePolicyProvider(
            store: store,
            source: CompanyPolicySource(),
            cache: FileRoutePolicyCache(url: cacheURL),
            strategy: .standard
        )
    }

    func start() async {
        _ = await provider.bootstrap() // restore trusted cache; no network wait
        _ = await provider.refresh()   // refresh in the background
    }

    func appBecameActive() async {
        _ = await provider.refreshIfNeeded()
    }
}
```

Put the cache in Application Support. When the Provider is used, pass
`policySession.store` to the direct modifier or coordinator. With local policy
only, pass `policy: localPolicy` instead; do not pass both.

## Coordinate competing route requests

Use one `ModuleRouteCoordinator` per scene if a notification, Universal Link,
and in-app action can arrive together. It gives navigation a small waiting line:

- Exact duplicate URLs are merged.
- Priority is `critical`, `external`, `userInitiated`, then `background`.
- Equal priorities keep arrival order.
- Ten requests wait by default; requests expire after 30 seconds.
- Policy is checked again just before navigation, so a newly opened circuit
  breaker still applies.

```swift
let coordinator = ModuleRouteCoordinator(
    router: router,
    registry: AppRoutes.registry,
    allowedHosts: ["example.com"],
    policyStore: policySession.store,
    configuration: ModuleRouteCoordinatorConfiguration(
        maximumPendingRequests: 10,
        defaultTimeToLive: 30,
        transitionDelay: .milliseconds(350)
    )
)
```

Install it with `.moduleLinkRouting(coordinator: coordinator)`. Do not create a
coordinator in each button. App-owned requests may call
`route(_:priority:expiresAt:)`; `openURL` and Universal Links use `.external`.

## Observe routes without collecting sensitive URLs

`ModuleRouteEvent` is a routing breadcrumb: it reports whether a request was
handled, malformed, blocked by policy, or dropped from the queue. It includes a
trace ID, host, module ID, route ID, presentation, outcome, and stable failure
code—but never query values.

```swift
@MainActor
final class AppRouteObserver: ModuleRouteObserving {
    func record(_ event: ModuleRouteEvent) {
        logger.info("route=\(event.outcome.rawValue) code=\(event.failureCode ?? "handled")")
        metrics.increment("route.\(event.failureCode ?? "handled")")
    }
}
```

`logger` and `metrics` are your app's adapters. Do not use a full URL, article
ID, token, or personal information as a metric label. Start with success rate,
top failure codes, and queue-full/expiry counts.

## Protect published URLs with contract CI

`RouteContracts.json` is the one source-controlled catalog of public routes in
the App root, not a file copied into every Feature Package. In the same pull
request that changes a public route, update the Feature parser and URL builder,
regenerate the catalog, update tests, and add any migration note.

CI validates the catalog and compares it with the PR base commit. It rejects an
accidental removal or incompatible change to a path, presentation, required
parameter, or supported contract version. Treat an intentional break as a
major-version change with a migration plan.

```bash
swift Scripts/update_route_contracts.swift --check
swift Scripts/validate_route_contract.swift RouteContracts.json
```

Run the update command without `--check` to write the current catalog. Add the
following Xcode **Run Script** build phase before compiling sources to make
every local build reject an out-of-date catalog. Replace the URLRouter path
with the location used by your App:

```bash
unset SDKROOT
swift "${SRCROOT}/Vendor/URLRouter/Scripts/update_route_contracts.swift" \
  --app-root "${SRCROOT}" \
  --check
swift "${SRCROOT}/Vendor/URLRouter/Scripts/generate_route_catalog.swift" \
  --app-root "${SRCROOT}" \
  --contracts RouteContracts.json \
  --output docs/route-catalog.html
```

Use `--check` in a build phase so the build does not modify tracked source
files. Because the generator recursively reads local Feature Packages, either
list every scanned source directory as a build-phase input or set
`ENABLE_USER_SCRIPT_SANDBOXING = NO` for this trusted script (the demo uses the
latter). Run the updating form deliberately before committing; use the same
check command in CI. The second command refreshes the local, searchable route
catalog after every successful contract check.

## A practical rollout order

1. Ship one versioned URL and its Feature resolver.
2. Add Universal Links and tests.
3. Generate `RouteContracts.json` at the App root before other teams depend on the URL.
4. Add observability when support needs diagnosis.
5. Add the Provider when operations needs safe remote restrictions.
6. Add the coordinator when route sources actually compete.
