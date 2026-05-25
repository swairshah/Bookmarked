// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "Bookmarked",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(name: "Bookmarked", targets: ["Bookmarked"]),
        .executable(name: "bookmarkedctl", targets: ["BookmarkedCLI"]),
        .library(name: "BookmarkedClient", targets: ["BookmarkedClient"])
    ],
    targets: [
        .target(
            name: "BookmarkedClient",
            path: "Sources/BookmarkedClient"
        ),
        .executableTarget(
            name: "Bookmarked",
            dependencies: ["BookmarkedClient"],
            path: "Sources/BookmarkedApp",
            exclude: ["Info.plist"],
            resources: [
                .process("Assets.xcassets"),
                .copy("Resources")
            ]
        ),
        .executableTarget(
            name: "BookmarkedCLI",
            dependencies: ["BookmarkedClient"],
            path: "Sources/BookmarkedCLI"
        ),
        .testTarget(
            name: "BookmarkedTests",
            dependencies: ["Bookmarked", "BookmarkedClient"],
            path: "Tests/BookmarkedTests"
        )
    ]
)
