// swift-tools-version: 6.2
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "Departure",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [
        .library(name: "Departure", targets: ["Departure"]),
    ],
    dependencies: [
    ],
    targets: [
        .target(
            name: "Departure",
            dependencies: [
            ],
            swiftSettings: [
                .defaultIsolation(MainActor.self)
            ]
        ),
        .testTarget(
            name: "DepartureTests",
            dependencies: ["Departure"]
        ),
    ],
    swiftLanguageModes: [.v6]
)
