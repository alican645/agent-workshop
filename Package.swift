// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "AjanTakip",
    platforms: [.macOS(.v26)],
    dependencies: [
        .package(url: "https://github.com/migueldeicaza/SwiftTerm", from: "1.20.0"),
    ],
    targets: [
        .target(name: "AjanTakipCore"),
        .executableTarget(name: "AjanTakip", dependencies: ["AjanTakipCore"]),
        .executableTarget(name: "Atolye", dependencies: ["AjanTakipCore", "AtolyeHostKit",
                                                       .product(name: "SwiftTerm", package: "SwiftTerm")], exclude: ["Web"]),
        .target(name: "AtolyeHostKit", dependencies: ["AjanTakipCore", .product(name: "SwiftTerm", package: "SwiftTerm")]),
        .executableTarget(name: "atolye-host", dependencies: ["AtolyeHostKit"]),
        .testTarget(name: "AjanTakipCoreTests", dependencies: ["AjanTakipCore"]),
        .testTarget(name: "AtolyeHostKitTests", dependencies: ["AtolyeHostKit"]),
    ]
)
