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
    targets: [
        .executableTarget(
            name: "DockTap",
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
