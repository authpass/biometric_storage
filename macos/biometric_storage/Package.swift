// swift-tools-version: 5.9
// The Swift Package Manager manifest for the macOS implementation of the
// `biometric_storage` plugin. Mirrors macos/biometric_storage.podspec so the
// plugin builds under both SPM (this file) and CocoaPods (the podspec), which
// share the same sources under Sources/biometric_storage/.
import PackageDescription

let package = Package(
  name: "biometric_storage",
  platforms: [
    .macOS("10.14")
  ],
  products: [
    .library(name: "biometric-storage", targets: ["biometric_storage"])
  ],
  dependencies: [
    // Flutter exposes the engine (FlutterMacOS) to plugin SPM targets via a
    // generated FlutterFramework package resolved at build time.
    .package(name: "FlutterFramework", path: "../FlutterFramework")
  ],
  targets: [
    .target(
      name: "biometric_storage",
      dependencies: [
        .product(name: "FlutterFramework", package: "FlutterFramework")
      ]
    )
  ]
)
