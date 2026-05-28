// swift-tools-version: 5.9

import PackageDescription

let package = Package(
    name: "DockTap",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(name: "DockTap", targets: ["DockTap"])
    ],
    dependencies: [
        .package(url: "https://github.com/sparkle-project/Sparkle", from: "2.6.0")
    ],
    targets: [
        .executableTarget(
            name: "DockTap",
            dependencies: [
                .product(name: "Sparkle", package: "Sparkle")
            ],
            path: "Sources/DockTap"
        ),
        .testTarget(
            name: "DockTapTests",
            dependencies: ["DockTap"],
            path: "Tests/DockTapTests",
            resources: [.copy("Fixtures")]
        )
    ]
)
