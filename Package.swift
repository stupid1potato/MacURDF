// swift-tools-version: 5.9
import PackageDescription

/// MacURDF workspace package (SPM). macOS 14+ app sources live under MacURDFApp.
/// Open in Xcode: File > Open > /workspace/macurdf/Package.swift
/// Then add a macOS App target in Xcode that embeds these sources, OR use the
/// MacURDFApp/Xcode scaffolding notes in MacURDFApp/README.md.
let package = Package(
    name: "MacURDF",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "MacURDFAppLib", targets: ["MacURDFApp"]),
    ],
    dependencies: [
        .package(path: "Packages/URDFCore"),
    ],
    targets: [
        .target(
            name: "MacURDFApp",
            dependencies: [
                .product(name: "URDFCore", package: "URDFCore"),
            ],
            path: "MacURDFApp/Sources/MacURDFApp"
        ),
    ]
)
