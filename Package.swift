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
        .executableTarget(name: "atolye-host", dependencies: ["AtolyeCore", "AtolyeHostKit"]),
        .executableTarget(name: "atolye-hook"),
        // Geliştirici aracı: gerçek Claude ekranlarını ayrıştırıcı testleri için dosyaya yakalar.
        .executableTarget(name: "prompt-capture", dependencies: ["AtolyeHostKit", .product(name: "SwiftTerm", package: "SwiftTerm")]),
        .testTarget(name: "AtolyeCoreTests", dependencies: ["AtolyeCore"], resources: [.copy("Fixtures")]),
        .testTarget(name: "AtolyeHostKitTests", dependencies: ["AtolyeHostKit"]),
    ]
)
