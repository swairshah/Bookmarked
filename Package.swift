// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "Bookmarked",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(name: "Bookmarked", targets: ["Bookmarked"])
    ],
    targets: [
        .executableTarget(
            name: "Bookmarked",
            path: "Sources/BookmarkedApp",
            exclude: ["Info.plist"],
            resources: [
                .process("Assets.xcassets"),
                .copy("Resources")
            ]
        ),
        .testTarget(
            name: "BookmarkedTests",
            dependencies: ["Bookmarked"],
            path: "Tests/BookmarkedTests"
        )
    ]
)
