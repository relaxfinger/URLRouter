import PackageDescription

let package = Package(
    name: "URLRouter",
    product: [
        .library(name: "URLRouter", targets: ["URLRouter"]),
    ],
    targets: [
        .target(
            name: "URLRouter"
        )
    ]
)
