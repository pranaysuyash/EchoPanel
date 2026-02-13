// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "MeetingListenerApp",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(name: "MeetingListenerApp", targets: ["MeetingListenerApp"])
    ],
    dependencies: [
        .package(url: "https://github.com/pointfreeco/swift-snapshot-testing", from: "1.17.4")
    ],
    targets: [
        .executableTarget(
            name: "MeetingListenerApp",
            path: "Sources"
        ),
        .testTarget(
            name: "MeetingListenerAppTests",
            dependencies: [
                "MeetingListenerApp",
                .product(name: "SnapshotTesting", package: "swift-snapshot-testing")
            ],
            path: "Tests",
            exclude: ["__Snapshots__"]
        )
    ]
)
