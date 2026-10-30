// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "StockBar",
    platforms: [.macOS(.v15)],
    targets: [
        .executableTarget(
            name: "StockBar",
            path: "Sources/StockBar"
        ),
    ],
    swiftLanguageModes: [.v5]
)
