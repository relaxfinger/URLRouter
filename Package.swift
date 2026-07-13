// swift-tools-version:6.0

import PackageDescription

let package = Package(
    name: "URLRouter",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [
        .library(
            name: "URLRouter",
            targets: ["URLRouter"]
        ),
            
    ],
    dependencies: [],
    targets: [
        .target(
            name: "URLRouter",
            dependencies: [],
            path: "URLRouter",
            exclude: ["Info.plist"]
        ),
        .testTarget(
            name: "URLRouterTests",
            dependencies: ["URLRouter"],
            path: "URLRouterTests",
            exclude: ["Info.plist"]
        ),
    ]
)
