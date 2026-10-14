// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "ShutUpTheMac",
    platforms: [.macOS(.v15)],
    targets: [
        .target(name: "ShutUpCore", path: "Sources/ShutUpCore",
                swiftSettings: [.swiftLanguageMode(.v5)]),
        .executableTarget(name: "shutup", dependencies: ["ShutUpCore"], path: "Sources/shutup",
                          swiftSettings: [.swiftLanguageMode(.v5)]),
        .executableTarget(name: "ShutUpApp", dependencies: ["ShutUpCore"], path: "Sources/ShutUpApp",
                          swiftSettings: [.swiftLanguageMode(.v5)]),
    ]
)
