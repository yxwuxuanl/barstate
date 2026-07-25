// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "BarState",
    defaultLocalization: "en",
    platforms: [
        .macOS("15.0")
    ],
    products: [
        .library(name: "BarStateCore", targets: ["BarStateCore"]),
        .executable(name: "BarState", targets: ["BarState"]),
        .executable(name: "BarStateScriptService", targets: ["BarStateScriptService"])
    ],
    targets: [
        .target(
            name: "BarStateCore",
            resources: [
                .process("Resources")
            ],
            linkerSettings: [
                .linkedFramework("JavaScriptCore")
            ]
        ),
        .executableTarget(
            name: "BarState",
            dependencies: ["BarStateCore"],
            linkerSettings: [
                .linkedFramework("AppKit"),
                .linkedFramework("Network"),
                .linkedFramework("ServiceManagement")
            ]
        ),
        .executableTarget(
            name: "BarStateScriptService",
            dependencies: ["BarStateCore"],
            linkerSettings: [
                .linkedFramework("JavaScriptCore")
            ]
        ),
        .testTarget(
            name: "BarStateCoreTests",
            dependencies: ["BarStateCore"]
        ),
        .testTarget(
            name: "BarStateTests",
            dependencies: ["BarState", "BarStateCore"]
        )
    ]
)
