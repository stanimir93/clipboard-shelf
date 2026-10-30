// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "Copykeep",
    platforms: [.macOS(.v14)],
    targets: [
        // The menu bar app: watches the clipboard and pastes from its history.
        .executableTarget(name: "Copykeep", path: "Sources/Copykeep"),
    ]
)
