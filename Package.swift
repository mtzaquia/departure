// swift-tools-version: 6.2
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "Departure",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [
        .library(name: "Departure", targets: ["Departure"]),
//        .library(name: "DepartureSwiftUI", targets: ["DepartureSwiftUI"]),
    ],
    targets: [
        .target(
            name: "Departure",
            swiftSettings: [
                .defaultIsolation(MainActor.self)
            ]
        ),
        .testTarget(
            name: "DepartureTests",
            dependencies: ["Departure"]
        ),
//        .target(
//            name: "DepartureSwiftUI",
//            swiftSettings: [
//                .defaultIsolation(MainActor.self)
//            ]
//        ),
//        .testTarget(
//            name: "DepartureSwiftUITests",
//            dependencies: ["DepartureSwiftUI"]
//        ),
    ],
    swiftLanguageModes: [.v6]
)
