// swift-tools-version:5.9
import PackageDescription

var products: [Product] = [
    .library(name: "DealerCore", targets: ["DealerCore"]),
    .executable(name: "deal", targets: ["deal"]),
]

var dependencies: [Package.Dependency] = []

var targets: [Target] = [
    .target(name: "DealerCore"),
    .executableTarget(name: "deal", dependencies: ["DealerCore"]),
    .testTarget(name: "DealerCoreTests", dependencies: ["DealerCore"]),
]

// The menu-bar app needs AppKit (and Sparkle for updates), so it only exists when building on
// macOS. Everything it relies on lives in DealerCore, which builds and tests on Linux too.
// Keep the Sparkle version in sync with SPARKLE_VERSION in scripts/make-appcast.sh.
#if os(macOS)
dependencies.append(.package(url: "https://github.com/sparkle-project/Sparkle", exact: "2.10.0"))
products.append(.executable(name: "Dealer", targets: ["Dealer"]))
targets.append(.executableTarget(
    name: "Dealer",
    dependencies: ["DealerCore", .product(name: "Sparkle", package: "Sparkle")]
))
#endif

let package = Package(
    name: "Dealer",
    platforms: [.macOS(.v13)],
    products: products,
    dependencies: dependencies,
    targets: targets
)
