# Contributing to URLRouter

Thanks for contributing. URLRouter is an iOS 17+, Swift 6, SwiftUI project that uses URL contracts and local Swift Package feature modules.

## Before you start

- Use the current stable Xcode release with Swift 6 support.
- Keep the minimum deployment target at iOS 17.
- Read the English [README](README.md) or [Chinese README](README.zh-CN.md) before changing routing behavior.

## Local validation

Run all checks before opening a pull request:

```bash
swift test
swift Scripts/validate_route_contract.swift RouteContracts.json
swift package diagnose-api-breaking-changes origin/master \
  --products URLRouter \
  --products URLRouterPolicyProvider
swift build --package-path Features/NavigationFeature
swift build --package-path Features/ContentFeature
xcodebuild build \
  -project URLRouter.xcodeproj \
  -scheme URLRouterDemo \
  -sdk iphonesimulator \
  -destination 'generic/platform=iOS Simulator' \
  CODE_SIGNING_ALLOWED=NO
```

## Routing rules

- Feature views navigate only with `openURL`.
- A route URL must include one of: `presentation=push`, `tab`, `sheet`, or `fullScreenCover`.
- A Feature Package owns its path matching and destination views through one `RouteModule`.
- Feature Packages communicate through documented URL contracts; do not import one feature from another just to navigate.

## Pull requests

- Branch from the latest `master` and target `master`.
- Keep each pull request focused on one concern.
- Add or update tests for observable behavior changes.
- Update both README languages when a public API or integration workflow changes.
- Read [MAINTENANCE.md](MAINTENANCE.md) before proposing a compatibility-sensitive change.
- Add an ADR under `docs/adr/` for a material public-boundary, route-compatibility, security, or long-term maintenance decision.
- Use concise, imperative commit messages, for example: `Add route registry collision test`.
- Wait for the required CI checks and maintainer approval before merging.
- Maintainers use squash merge so each pull request becomes one focused commit on `master`.

Direct pushes to `master` are not part of the normal contribution workflow. Releases are created from `master` and identified with semantic version tags such as `v2.0.0`.

By contributing, you agree that your contribution is licensed under this repository's [MIT License](LICENSE).
