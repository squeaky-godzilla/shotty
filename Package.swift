// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "Shotty",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "Shotty",
            path: "Shotty/Sources"
        )
    ]
)
