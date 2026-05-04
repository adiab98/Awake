// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "Awake",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "Awake", targets: ["Awake"])
    ],
    targets: [
        .executableTarget(
            name: "Awake",
            path: "Sources/Awake"
        ),
        .testTarget(
            name: "AwakeTests",
            dependencies: ["Awake"]
        )
    ]
)
