// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "Atolye",
    platforms: [.macOS(.v26)],
    dependencies: [
        .package(url: "https://github.com/migueldeicaza/SwiftTerm", from: "1.20.0"),
    ],
    targets: [
        .target(name: "AtolyeCore"),
        .executableTarget(name: "Atolye", dependencies: ["AtolyeCore", "AtolyeHostKit",
                                                       .product(name: "SwiftTerm", package: "SwiftTerm")], exclude: ["Web"]),
        .target(name: "AtolyeHostKit", dependencies: ["AtolyeCore", .product(name: "SwiftTerm", package: "SwiftTerm")]),
        .executableTarget(name: "atolye-host", dependencies: ["AtolyeHostKit"]),
        .testTarget(name: "AtolyeCoreTests", dependencies: ["AtolyeCore"]),
        .testTarget(name: "AtolyeHostKitTests", dependencies: ["AtolyeHostKit"]),
    ]
)
