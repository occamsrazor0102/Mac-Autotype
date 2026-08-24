// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "AutoType",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .library(name: "AutoTypeCore", targets: ["AutoTypeCore"]),
        .executable(name: "AutoType", targets: ["AutoTypeApp"])
    ],
    targets: [
        .target(
            name: "AutoTypeCore",
            path: "Sources/AutoTypeCore"
        ),
        .executableTarget(
            name: "AutoTypeApp",
            dependencies: ["AutoTypeCore"],
            path: "Sources/AutoTypeApp",
            linkerSettings: [
                .linkedFramework("ApplicationServices"),
                .linkedFramework("Carbon"),
                .linkedFramework("Cocoa"),
                .linkedFramework("ServiceManagement")
            ]
        ),
        .testTarget(
            name: "AutoTypeCoreTests",
            dependencies: ["AutoTypeCore"],
            path: "Tests/AutoTypeCoreTests"
        )
    ],
    swiftLanguageModes: [.v5]
)
