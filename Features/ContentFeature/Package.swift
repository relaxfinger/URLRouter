// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "ContentFeature",
    platforms: [.iOS(.v17)],
    products: [.library(name: "ContentFeature", targets: ["ContentFeature"])],
    dependencies: [.package(path: "../..")],
    targets: [
        .target(
            name: "ContentFeature",
            dependencies: [.product(name: "URLRouter", package: "URLRouter")]
        )
    ]
)
