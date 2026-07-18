// swift-tools-version:6.0

import PackageDescription

let package = Package(
    name: "URLRouter",
    defaultLocalization: "en",
    platforms: [.iOS(.v17), .macOS(.v14)],
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
