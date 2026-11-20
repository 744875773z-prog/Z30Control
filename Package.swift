// swift-tools-version: 5.9
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "Z30Control",
    platforms: [
        .iOS(.v16),
        .macOS(.v13)
    ],
    products: [
        .library(
            name: "Z30Control",
            targets: ["Z30Control"]
        ),
    ],
    targets: [
        .target(
            name: "Z30Control",
            path: "Z30Control"
        ),
        .testTarget(
            name: "Z30ControlTests",
            dependencies: ["Z30Control"],
            path: "Tests"
        ),
    ]
)
