# Changelog

All notable changes are documented here. This project follows [Semantic Versioning](https://semver.org/).

## [Unreleased]

## [2.5.6] - 2026-07-23

### Changed

- Streamline the README route-contract section around the two plugin products
  and link detailed setup instructions to the dedicated workflow guide.

## [2.5.5] - 2026-07-23

### Changed

- Extend route-contract inference for resolvers that alias
  `link.pathComponents`, bind path parameters to local variables, and keep URL
  builders in App-owned source rather than the Feature Package.
- Match concrete sample URLs such as `/articles/42` to parameterized route
  contracts such as `/articles/:id`.

## [2.5.4] - 2026-07-23

### Added

- Add an App-owned `app/diagnostics` route to URLRouterDemo to demonstrate
  routing UI that is not extracted into a Feature Package.

### Changed

- Create a missing `RouteContracts.json` automatically when generating the
  route catalog, so first-run catalog generation succeeds.
- Make the Demo build phase generate contracts and the catalog on its first
  build instead of failing a validation-only check.

## [2.5.3] - 2026-07-23

### Changed

- Scan App-owned Swift sources in addition to independent Feature Packages when
  generating route contracts and the route catalog.
- Render App-owned routes in their own `App` catalog section while continuing
  to keep each Feature Package in a separate table.

## [2.5.2] - 2026-07-23

### Changed

- Group the generated route catalog by Feature Package, with per-Feature route
  tables, route counts, quick navigation, and Feature-aware search.
- Document the complete Xcode and SwiftPM workflow for the URLRouter build and
  command plugins, including expected outputs and troubleshooting.

## [2.5.1] - 2026-07-23

### Added

- Added remote Swift Package Manager route plugins: a build plugin for Xcode build-time contract validation and a command plugin for explicitly regenerating the tracked route contract and catalog.

### Changed

- Updated English and Chinese route-contract documentation to use the remote-SwiftPM plugin workflow without hard-coded checkout paths.

## [2.5.0] - 2026-07-20

### Added

- Added App-root route-contract generation and validation scripts that discover local Feature Packages, update the single `RouteContracts.json`, and generate a searchable local route catalog.
- Added a URLRouterDemo build phase that verifies route contracts and refreshes the route catalog on every build.

### Changed

- Documented the App-root ownership model for route contracts and the Xcode/CI integration workflow in English and Chinese.

## [2.4.7] - 2026-07-19

### Changed

- Reorganized the English and Chinese documentation into a concise README plus task-focused getting-started, architecture, and production-governance guides.
- Added a clear documentation map and aligned the beginner blog with the repository guides, so readers can move from the first route to production operations without duplicated or conflicting instructions.
- Refreshed repository metadata and documentation links for clearer discovery of the Swift Package, supported platforms, and practical integration path.

## [2.4.6] - 2026-07-18

### Added

- Added `ModuleRouteCoordinator` for per-scene serialized route handling, exact-URL deduplication, priority ordering, bounded queues, expiration, and policy revalidation before execution.
- Added coordinator tests and updated the demo plus English and Chinese guides with a plain-language concurrency model and integration example.

## [2.4.5] - 2026-07-18

### Added

- Added support, maintenance, and architecture-decision policies; CODEOWNERS; and weekly Dependabot updates for GitHub Actions and Swift dependencies.

## [2.4.4] - 2026-07-18

### Added

- PR CI now compares route contracts with the exact base commit and rejects removed routes, path changes, removed presentation styles, required parameters, or supported contract versions.

## [2.4.3] - 2026-07-18

### Added

- PR CI now compares the public Swift APIs of both library products against the exact base commit and rejects breaking changes.
- Added English and Chinese documentation for the public API compatibility policy and its relationship to semantic versioning.

## [2.4.2] - 2026-07-18

### Changed

- Expanded the production-governance guides in English and Chinese with plain-language explanations, operating examples, and integration steps for remote policy/circuit breaking, observability, and route-contract CI.
- Added English comments at URLRouter integration points in the demo so the scene host, policy lifecycle, observability, and circuit-breaker behavior are easy to follow.

## [2.4.1] - 2026-07-18

### Added

- Optional `URLRouterPolicyProvider` product for cache-first remote-policy loading, TTL refreshes, stale-cache fallback, atomic policy replacement, and file or in-memory caching.
- Extensible remote-source and payload-validation protocols so apps can use their own HTTP client, remote-config vendor, signed envelopes, and authentication.

### Changed

- Updated the demo and English/Chinese guides with the recommended App lifecycle: cache first, background refresh, foreground TTL refresh, and safe fallback.

## [2.4.0] - 2026-07-18

### Added

- `ModuleRoutePolicyStore` and Codable `ModuleRouteRemotePolicy` for remotely managed route restrictions, per-module controls, and an emergency circuit breaker.
- Vendor-neutral `ModuleRouteObservability`, stable failure codes, and observer fan-out for logging, metrics, and tracing adapters.
- Source-controlled `RouteContracts.json` and CI validation for route identity, path/presentation uniqueness, and required URL parameters.

### Changed

- Updated the demo with a live routing circuit-breaker control and telemetry status.
- Updated English and Chinese integration guides with remote-policy, observability, and contract-CI guidance.

## [2.3.0] - 2026-07-18

### Added

- `ModuleRoutePolicy` for versioned URL contracts, module feature flags, authorization, and presentation governance.
- Privacy-conscious `ModuleRouteEvent` telemetry with trace IDs and route metadata.

### Changed

- Made repeated push and modal requests idempotent.
- Updated the demo and integration guides with strict contract enforcement and telemetry examples.

## [2.2.0] - 2026-07-18

### Added

- Registry validation for duplicate module IDs, cross-module route ownership, and missing destinations.
- `onFailure` callbacks for route configuration and URL-contract failures.

### Changed

- Made modal routing deterministic: one modal route is active at a time, and push/tab navigation dismisses it.
- Expanded URL validation and registry-state test coverage.
- Updated CI to use the current GitHub checkout action runtime.

## [2.1.0] - 2026-07-18

### Added

- tvOS 17+ and watchOS 10+ support for URLRouter and its local Feature Packages.
- Cross-platform `RouterHost` support for iOS, macOS, tvOS, and watchOS.

### Changed

- Expanded platform and demo documentation to cover every supported Apple platform.

## [2.0.3] - 2026-07-18

### Changed

- Standardized the documented platform baseline on Apple's 2023 release generation: iOS 17+ and macOS 14+.
- Applied the same platform-generation policy to the root package and both local Feature Packages.

## [2.0.2] - 2026-07-18

### Changed

- Reorganized the library and its tests into the standard Swift Package Manager `Sources/` and `Tests/` layout.
- Simplified the package manifest and kept the Xcode demo project aligned with the new source locations.

### Added

- Module-owned URL routing with `presentation=push`, `tab`, `sheet`, or `fullScreenCover`.
- Local `NavigationFeature` and `ContentFeature` demo packages.
- PR CI, contribution guidance, and GitHub contribution templates.

## [1.0.0] - 2026-07-14

### Added

- iOS 17+ SwiftUI Universal Link validation.
- Feature module registry and `openURL`-based routing.
- Push, tab, sheet, and full-screen-cover URL presentations.
- English and Chinese integration documentation.

## Versioning policy

- **MAJOR**: removes or changes a public API or URL contract.
- **MINOR**: adds backwards-compatible public capability.
- **PATCH**: fixes behavior or documentation without changing the public contract.
