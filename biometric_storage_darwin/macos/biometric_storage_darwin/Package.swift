// swift-tools-version: 5.9

import PackageDescription

let package = Package(
    name: "biometric_storage_darwin",
    platforms: [
        .macOS("10.15")
    ],
    products: [
        .library(name: "biometric-storage-darwin", targets: ["biometric_storage_darwin"])
    ],
    dependencies: [
        .package(name: "FlutterFramework", path: "../FlutterFramework")
    ],
    targets: [
        .target(
            name: "biometric_storage_darwin",
            dependencies: [
                .product(name: "FlutterFramework", package: "FlutterFramework")
            ]
        )
    ]
)