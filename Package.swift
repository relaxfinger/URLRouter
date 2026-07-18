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
        ),
        .library(
            name: "URLRouterPolicyProvider",
            targets: ["URLRouterPolicyProvider"]
        )
    ],
    dependencies: [],
    targets: [
        .target(
            name: "URLRouter",
            dependencies: []
        ),
        .target(
            name: "URLRouterPolicyProvider",
            dependencies: ["URLRouter"]
        ),
        .testTarget(
            name: "URLRouterTests",
            dependencies: ["URLRouter"]
        ),
        .testTarget(
            name: "URLRouterPolicyProviderTests",
            dependencies: ["URLRouterPolicyProvider"]
        )
    ],
    swiftLanguageModes: [.v6]
)
