# Changelog

All notable changes are documented here. This project follows [Semantic Versioning](https://semver.org/).

## [Unreleased]

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
