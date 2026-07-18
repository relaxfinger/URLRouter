// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "NavigationFeature",
    // Apple 2023 platform generation.
    platforms: [
        .iOS(.v17),
        .macOS(.v14),
        .tvOS(.v17),
        .watchOS(.v10)
    ],
    products: [.library(name: "NavigationFeature", targets: ["NavigationFeature"])],
    dependencies: [.package(path: "../..")],
    targets: [
        .target(
            name: "NavigationFeature",
            dependencies: [.product(name: "URLRouter", package: "URLRouter")]
        )
    ]
)
