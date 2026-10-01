// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "BoatDeck",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "BoatDeck",
            path: "Sources/BoatDeck"
        )
    ]
)
