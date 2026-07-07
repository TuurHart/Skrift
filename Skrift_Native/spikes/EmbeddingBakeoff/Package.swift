// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "EmbeddingBakeoff",
    platforms: [.macOS(.v15)],
    dependencies: [
        .package(url: "https://github.com/john-rocky/CoreML-LLM", from: "1.9.0"),
    ],
    targets: [
        .executableTarget(
            name: "bakeoff",
            dependencies: [.product(name: "CoreMLLLM", package: "CoreML-LLM")]
        ),
    ],
    swiftLanguageModes: [.v5]
)
