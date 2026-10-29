// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "StockBar",
    platforms: [.macOS(.v15)],
    targets: [
        .executableTarget(
            name: "StockBar",
            dependencies: ["llama"],
            path: "Sources/StockBar",
            // The app bundle carries llama.framework in Contents/Frameworks (see build.sh).
            linkerSettings: [.unsafeFlags(["-Xlinker", "-rpath", "-Xlinker", "@executable_path/../Frameworks"])]
        ),
        // llama.cpp, for the on-device model in the AI tab. build.sh downloads the pinned release into Vendor/.
        .binaryTarget(name: "llama", path: "Vendor/llama.xcframework"),
    ],
    swiftLanguageModes: [.v5]
)
