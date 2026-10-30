// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "Runway",
    platforms: [.macOS(.v14)],
    dependencies: [
.package(url: "https://github.com/gonzalezreal/swift-markdown-ui", from: "2.4.1")
    ],
    targets: [
        .executableTarget(
            name: "Runway",
            dependencies: [
                .product(name: "MarkdownUI", package: "swift-markdown-ui")
            ],
            path: "Sources/Runway"
        ),
        .testTarget(
            name: "RunwayTests",
            dependencies: ["Runway"],
            path: "Tests/RunwayTests"
        )
    ],
    swiftLanguageModes: [.v6]
)
