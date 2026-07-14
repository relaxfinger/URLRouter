// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "NavigationFeature",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [.library(name: "NavigationFeature", targets: ["NavigationFeature"])],
    dependencies: [.package(path: "../..")],
    targets: [
        .target(
            name: "NavigationFeature",
            dependencies: [.product(name: "URLRouter", package: "URLRouter")]
        )
    ]
)
