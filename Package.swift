// swift-tools-version: 5.7
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "AbbreviationExpander",
    platforms: [
        .macOS(.v12)
    ],
    products: [
        .executable(
            name: "AbbreviationExpander",
            targets: ["AbbreviationExpander"]
        )
    ],
    dependencies: [],
    targets: [
        .executableTarget(
            name: "AbbreviationExpander",
            dependencies: [],
            path: "Sources/AbbreviationExpander"
        ),
        .testTarget(
            name: "AbbreviationExpanderTests",
            dependencies: ["AbbreviationExpander"],
            path: "Tests/AbbreviationExpanderTests"
        )
    ]
)
