// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "ContentFeature",
    // Apple 2023 platform generation: iOS 17 and macOS 14.
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [.library(name: "ContentFeature", targets: ["ContentFeature"])],
    dependencies: [.package(path: "../..")],
    targets: [
        .target(
            name: "ContentFeature",
            dependencies: [.product(name: "URLRouter", package: "URLRouter")]
        )
    ]
)
