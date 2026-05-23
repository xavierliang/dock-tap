// swift-tools-version: 5.9

import PackageDescription

let package = Package(
    name: "DockTapProbe",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(name: "DockTapProbe", targets: ["DockTapProbe"])
    ],
    targets: [
        .executableTarget(
            name: "DockTapProbe",
            path: "Sources/DockTapProbe"
        ),
        .testTarget(
            name: "DockTapProbeTests",
            dependencies: ["DockTapProbe"],
            path: "Tests/DockTapProbeTests"
        )
    ]
)
