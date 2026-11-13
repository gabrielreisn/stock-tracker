// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "Cymba",
    platforms: [.macOS(.v15)],
    targets: [
        .executableTarget(
            name: "Cymba",
            path: "Sources/StockBar"
        ),
    ],
    swiftLanguageModes: [.v5]
)
