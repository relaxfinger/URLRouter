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

- Branch from `develop` and target `develop` unless the maintainer asks otherwise.
- Keep each pull request focused on one concern.
- Add or update tests for observable behavior changes.
- Update both README languages when a public API or integration workflow changes.
- Use concise, imperative commit messages, for example: `Add route registry collision test`.

By contributing, you agree that your contribution is licensed under this repository's [MIT License](LICENSE).
