// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "FileNameChange",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(name: "FileNameChange", targets: ["FileNameChange"])
    ],
    targets: [
        .target(
            name: "FileNameCore",
            path: "Sources/FileNameCore"
        ),
        .executableTarget(
            name: "FileNameChange",
            dependencies: ["FileNameCore"],
            path: "Sources/FileNameChange"
        ),
        .testTarget(
            name: "FileNameCoreTests",
            dependencies: ["FileNameCore"],
            path: "Tests/FileNameCoreTests"
        )
    ]
)
