// swift-tools-version:5.2
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "InterposeKit",
    platforms: [
       .iOS(.v11),
       .macOS(.v10_13),
       .tvOS(.v11),
       .watchOS(.v5)
     ],
    products: [
        // Products define the executables and libraries produced by a package, and make them visible to other packages.
        .library(
            name: "InterposeKit",
            targets: ["InterposeKit"]),
    ],
    targets: [
        // Targets are the basic building blocks of a package. A target can define a module or a test suite.
        // Targets can depend on other targets in this package, and on products in packages which this package depends on.
        .target(
            name: "InterposeKit",
            dependencies: []),
        .testTarget(
            name: "InterposeKitTests",
            dependencies: ["InterposeKit"]),
    ]
)
