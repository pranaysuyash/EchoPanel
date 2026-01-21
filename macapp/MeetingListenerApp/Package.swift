// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "MeetingListenerApp",
    platforms: [.macOS(.v13)],
    products: [
        .executable(name: "MeetingListenerApp", targets: ["MeetingListenerApp"])
    ],
    dependencies: [],
    targets: [
        .executableTarget(
            name: "MeetingListenerApp",
            dependencies: []
        )
    ]
)
