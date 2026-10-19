// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "UltimaXB",
    platforms: [.macOS(.v13)],
    products: [.executable(name: "UltimaMac", targets: ["UltimaMac"])],
    targets: [
        .target(name: "UOCore"),
        .executableTarget(name: "UltimaMac", dependencies: ["UOCore"], resources: [.copy("Resources")]),
        .testTarget(name: "UOCoreTests", dependencies: ["UOCore"])
    ]
)
