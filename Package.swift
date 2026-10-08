// swift-tools-version:5.7
import PackageDescription

let package = Package(
    name: "swift-audio-switcher",
    platforms: [.macOS(.v13)],
    products: [
        .executable(name: "swift-audio-switcher", targets: ["swift-audio-switcher"]),
        .executable(name: "airplay-pick", targets: ["airplay-pick"])
    ],
    targets: [
        .executableTarget(
            name: "swift-audio-switcher",
            path: "Sources/swift-audio-switcher"
        ),
        .executableTarget(
            name: "airplay-pick",
            path: "Sources/airplay-pick"
        )
    ]
)
