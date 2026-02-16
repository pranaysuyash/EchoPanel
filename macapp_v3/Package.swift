// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "EchoPanelV3",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "EchoPanelV3", targets: ["EchoPanelV3"])
    ],
    dependencies: [],
    targets: [
        .executableTarget(
            name: "EchoPanelV3",
            path: "Sources"
        )
    ]
)
