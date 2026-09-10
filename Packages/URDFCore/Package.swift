// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "URDFCore",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .library(
            name: "URDFCore",
            targets: ["URDFCore"]
        )
    ],
    targets: [
        .target(
            name: "URDFCore",
            path: "Sources/URDFCore"
        ),
        .testTarget(
            name: "URDFCoreTests",
            dependencies: ["URDFCore"],
            path: "Tests/URDFCoreTests"
        )
    ]
)
