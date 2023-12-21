// swift-tools-version: 5.9
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "CensoSDK",
    platforms: [
        .macOS(.v13), .iOS(.v15)
    ],
    products: [
        // Products define the executables and libraries a package produces, making them visible to other packages.
        .library(
            name: "CensoSDK",
            targets: ["CensoSDK"]),
    ],
    dependencies: [
        .package(url: "https://github.com/attaswift/BigInt", .upToNextMajor(from: "5.1.0")),
    ],
    targets: [
        // Targets are the basic building blocks of a package, defining a module or a test suite.
        // Targets can depend on other targets in this package and products from dependencies.
        .target(
            name: "CensoSDK",
            dependencies: [.product(name: "BigInt", package: "BigInt")]),
        .testTarget(
            name: "CensoSDKTests",
            dependencies: ["CensoSDK"]),
    ]
)
