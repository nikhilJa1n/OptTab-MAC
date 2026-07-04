// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "AdvancedDock",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "AdvancedDock", targets: ["AdvancedDock"])
    ],
    dependencies: [],
    targets: [
        .executableTarget(
            name: "AdvancedDock",
            dependencies: [],
            path: "Sources"
        )
    ]
)
