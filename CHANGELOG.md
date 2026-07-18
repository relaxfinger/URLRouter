# Changelog

All notable changes are documented here. This project follows [Semantic Versioning](https://semver.org/).

## [Unreleased]

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
