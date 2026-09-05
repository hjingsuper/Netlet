// swift-tools-version: 5.10

import PackageDescription

let package = Package(
    name: "Netlet",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "Netlet", targets: ["Netlet"])
    ],
    dependencies: [
        .package(
            url: "https://github.com/sparkle-project/Sparkle",
            exact: "2.9.4"
        )
    ],
    targets: [
        .systemLibrary(
            name: "CSQLite",
            path: "Sources/CSQLite"
        ),
        .executableTarget(
            name: "Netlet",
            dependencies: [
                "CSQLite",
                .product(name: "Sparkle", package: "Sparkle")
            ],
            path: "Sources/Netlet"
        ),
        .testTarget(
            name: "NetletTests",
            dependencies: ["Netlet"]
        )
    ]
)
