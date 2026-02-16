// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "EchoPanelV2",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "EchoPanelV2", targets: ["EchoPanelV2"])
    ],
    dependencies: [],
    targets: [
        .executableTarget(
            name: "EchoPanelV2",
            path: "Sources"
        )
    ]
)
