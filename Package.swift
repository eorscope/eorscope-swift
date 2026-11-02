// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "EORScopeEmployerCosts",
    platforms: [.macOS(.v10_15), .iOS(.v13)],
    products: [
        .library(name: "EORScopeEmployerCosts", targets: ["EORScopeEmployerCosts"]),
    ],
    targets: [
        .target(
            name: "EORScopeEmployerCosts",
            resources: [.copy("data")]
        ),
        .testTarget(
            name: "EORScopeEmployerCostsTests",
            dependencies: ["EORScopeEmployerCosts"]
        ),
    ]
)
