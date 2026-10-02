// swift-tools-version: 5.9
import PackageDescription

// Throwaway spike: prove FluidAudio diarization splits a recording into speakers
// before building conversation mode into the app. Run:
//   swift run DiarizeSpike <path-to-m4a>
let package = Package(
    name: "DiarizeSpike",
    platforms: [.macOS(.v14)],
    dependencies: [
        // Match the app's pin (branch: main).
        .package(url: "https://github.com/FluidInference/FluidAudio.git", branch: "main"),
    ],
    targets: [
        .executableTarget(
            name: "DiarizeSpike",
            dependencies: [.product(name: "FluidAudio", package: "FluidAudio")]
        ),
    ]
)
