// swift-tools-version:5.7
import PackageDescription

let package = Package(
    name: "swift-audio-switcher",
    platforms: [.macOS(.v11)],
    products: [
        .executable(name: "swift-audio-switcher", targets: ["swift-audio-switcher"])
    ],
    targets: [
        .executableTarget(
            name: "swift-audio-switcher",
            path: "Sources/swift-audio-switcher",
            cSettings: [
                .unsafeFlags(["-Wno-deprecated-declarations"])
            ],
            linkerSettings: [
                .linkedFramework("CoreAudio"),
                .linkedFramework("CoreFoundation"),
            ]
        )
    ]
)
