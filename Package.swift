// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "GimmeTheVerse",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "GimmeTheVerse",
            path: "Sources/GimmeTheVerse",
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
    ]
)
