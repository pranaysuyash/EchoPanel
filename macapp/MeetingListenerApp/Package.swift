// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "MeetingListenerApp",
    platforms: [
        .macOS(.v14)  // Required for MLX Audio Swift
    ],
    products: [
        .executable(name: "MeetingListenerApp", targets: ["MeetingListenerApp"])
    ],
    dependencies: [
        .package(url: "https://github.com/pointfreeco/swift-snapshot-testing", from: "1.17.4"),
        // MLX Audio Swift - Native ASR on Apple Silicon
        .package(url: "https://github.com/Blaizzy/mlx-audio-swift.git", branch: "main")
    ],
    targets: [
        .executableTarget(
            name: "MeetingListenerApp",
            dependencies: [
                .product(name: "MLXAudioSTT", package: "mlx-audio-swift"),
                .product(name: "MLXAudioVAD", package: "mlx-audio-swift")
            ],
            path: "Sources",
            exclude: ["ASR/README.md"]
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
