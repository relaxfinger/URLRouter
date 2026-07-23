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
        ),
        .plugin(
            name: "URLRouterRouteBuildPlugin",
            targets: ["URLRouterRouteBuildPlugin"]
        ),
        .plugin(
            name: "URLRouterRouteCommandPlugin",
            targets: ["URLRouterRouteCommandPlugin"]
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
        .plugin(
            name: "URLRouterRouteBuildPlugin",
            capability: .buildTool()
        ),
        .plugin(
            name: "URLRouterRouteCommandPlugin",
            capability: .command(
                intent: .custom(verb: "generate-urlrouter-contracts", description: "Generate URLRouter route contracts and catalog."),
                permissions: [.writeToPackageDirectory(reason: "Generate RouteContracts.json and the route catalog.")]
            )
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
