// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "Runway",
    platforms: [.macOS(.v14)],
    dependencies: [
        // GPU terminal engine: libghostty via the GhosttyKit wrapper.
        // Pinned to a specific commit — upstream's C API is still alpha, so we
        // deliberately avoid tracking a moving branch.
        .package(
            url: "https://github.com/briannadoubt/GhosttyKit.git",
            revision: "f3756807a61a42dba3dc1d866a1fd865f1ddfe21"
        ),
        .package(url: "https://github.com/gonzalezreal/swift-markdown-ui", from: "2.4.1")
    ],
    targets: [
        .executableTarget(
            name: "Runway",
            dependencies: [
                .product(name: "GhosttyKit", package: "GhosttyKit"),
                .product(name: "MarkdownUI", package: "swift-markdown-ui")
            ],
            path: "Sources/Runway"
        )
    ],
    swiftLanguageModes: [.v6]
)
