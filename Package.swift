// swift-tools-version: 5.9

import PackageDescription

let package = Package(
    name: "DockTap",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(name: "DockTap", targets: ["DockTap"]),
        .executable(name: "DockTapClosedLidHelper", targets: ["DockTapClosedLidHelper"])
    ],
    dependencies: [
        .package(url: "https://github.com/sparkle-project/Sparkle", from: "2.6.0")
    ],
    targets: [
        .target(
            name: "DockTapClosedLidIPC",
            path: "Sources/DockTapClosedLidIPC"
        ),
        .target(
            name: "DockTapClosedLidHelperCore",
            path: "Sources/DockTapClosedLidHelperCore"
        ),
        .executableTarget(
            name: "DockTapClosedLidHelper",
            dependencies: [
                "DockTapClosedLidIPC",
                "DockTapClosedLidHelperCore"
            ],
            path: "Sources/DockTapClosedLidHelper"
        ),
        .executableTarget(
            name: "DockTap",
            dependencies: [
                "DockTapClosedLidIPC",
                .product(name: "Sparkle", package: "Sparkle")
            ],
            path: "Sources/DockTap"
        ),
        .testTarget(
            name: "DockTapTests",
            dependencies: [
                "DockTap",
                "DockTapClosedLidIPC",
                "DockTapClosedLidHelperCore"
            ],
            path: "Tests/DockTapTests",
            resources: [.copy("Fixtures")]
        )
    ]
)
