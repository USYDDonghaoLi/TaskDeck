// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "TaskDeck",
    platforms: [.macOS(.v13)],
    products: [
        .executable(name: "TaskDeck", targets: ["TaskDeck"])
    ],
    targets: [
        .executableTarget(name: "TaskDeck")
    ]
)
