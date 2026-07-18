// swift-tools-version:6.0

import PackageDescription

let package = Package(
    name: "URLRouter",
    defaultLocalization: "en",
    // Apple 2023 platform generation.
    platforms: [
        .iOS(.v17),
        .macOS(.v14),
        .tvOS(.v17),
        .watchOS(.v10)
    ],
    products: [
        .library(
            name: "URLRouter",
            targets: ["URLRouter"]
        )
    ],
    dependencies: [],
    targets: [
        .target(
            name: "URLRouter",
            dependencies: []
        ),
        .testTarget(
            name: "URLRouterTests",
            dependencies: ["URLRouter"]
        )
    ],
    swiftLanguageModes: [.v6]
)
