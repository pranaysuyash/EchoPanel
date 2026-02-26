// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "MeetingListenerApp",
    platforms: [
        .macOS(.v15)
    ],
    products: [
        .executable(name: "MeetingListenerApp", targets: ["MeetingListenerApp"])
    ],
    dependencies: [
        .package(url: "https://github.com/pointfreeco/swift-snapshot-testing", from: "1.17.4"),
        // MLX Audio Swift - Native ASR on Apple Silicon
        .package(url: "https://github.com/Blaizzy/mlx-audio-swift.git", from: "0.1.0"),
        // MLX Swift LM - LLM + Embeddings for meeting analysis
        .package(url: "https://github.com/ml-explore/mlx-swift-lm.git", from: "2.30.6")
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
