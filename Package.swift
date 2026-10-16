// swift-tools-version:5.9
import PackageDescription

var products: [Product] = [
    .library(name: "DealerCore", targets: ["DealerCore"]),
    .executable(name: "deal", targets: ["deal"]),
]

var targets: [Target] = [
    .target(name: "DealerCore"),
    .executableTarget(name: "deal", dependencies: ["DealerCore"]),
    .testTarget(name: "DealerCoreTests", dependencies: ["DealerCore"]),
]

// The menu-bar app needs AppKit, so it only exists when building on macOS.
// Everything it relies on lives in DealerCore, which builds and tests on Linux too.
#if os(macOS)
products.append(.executable(name: "Dealer", targets: ["Dealer"]))
targets.append(.executableTarget(name: "Dealer", dependencies: ["DealerCore"]))
#endif

let package = Package(
    name: "Dealer",
    platforms: [.macOS(.v13)],
    products: products,
    targets: targets
)
