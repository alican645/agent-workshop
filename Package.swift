// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "AjanTakip",
    platforms: [.macOS(.v26)],
    targets: [
        .target(name: "AjanTakipCore"),
        .executableTarget(name: "AjanTakip", dependencies: ["AjanTakipCore"]),
        .executableTarget(name: "Atolye", dependencies: ["AjanTakipCore"], exclude: ["Web"]),
        .testTarget(name: "AjanTakipCoreTests", dependencies: ["AjanTakipCore"]),
    ]
)
