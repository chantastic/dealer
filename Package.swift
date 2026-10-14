// swift-tools-version:5.9
import PackageDescription

var products: [Product] = [
    .library(name: "EarlCore", targets: ["EarlCore"]),
    .executable(name: "earlctl", targets: ["earlctl"]),
]

var targets: [Target] = [
    .target(name: "EarlCore"),
    .executableTarget(name: "earlctl", dependencies: ["EarlCore"]),
    .testTarget(name: "EarlCoreTests", dependencies: ["EarlCore"]),
]

// The menu-bar app needs AppKit, so it only exists when building on macOS.
// Everything it relies on lives in EarlCore, which builds and tests on Linux too.
#if os(macOS)
products.append(.executable(name: "Earl", targets: ["Earl"]))
targets.append(.executableTarget(name: "Earl", dependencies: ["EarlCore"]))
#endif

let package = Package(
    name: "Earl",
    platforms: [.macOS(.v13)],
    products: products,
    targets: targets
)
