// swift-tools-version:5.10
import PackageDescription

let package = Package(
    name: "cqlb",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "CqlbCore", targets: ["CqlbCore"]),
        .executable(name: "cqlb-query", targets: ["CqlbQuery"]),
        .executable(name: "cqlb-repl", targets: ["CqlbRepl"]),
        .executable(name: "cqlb", targets: ["CqlbApp"]),
        .executable(name: "cqlb-settings", targets: ["CqlbSettings"]),
    ],
    targets: [
        .target(
            name: "CqlbCore",
            path: "Sources/CqlbCore"
        ),
        .executableTarget(
            name: "CqlbQuery",
            dependencies: ["CqlbCore"],
            path: "Sources/CqlbQuery"
        ),
        .executableTarget(
            name: "CqlbRepl",
            dependencies: ["CqlbCore"],
            path: "Sources/CqlbRepl"
        ),
        .executableTarget(
            name: "CqlbApp",
            dependencies: ["CqlbCore"],
            path: "Sources/CqlbApp",
            linkerSettings: [
                .linkedFramework("AppKit"),
                .linkedFramework("ApplicationServices"),
                .linkedFramework("Carbon"),
            ]
        ),
        .executableTarget(
            name: "CqlbSettings",
            dependencies: ["CqlbCore"],
            path: "Sources/CqlbSettings",
            linkerSettings: [
                .linkedFramework("AppKit"),
                .linkedFramework("SwiftUI"),
            ]
        ),
        .testTarget(
            name: "CqlbCoreTests",
            dependencies: ["CqlbCore"],
            path: "Tests/CqlbCoreTests"
        ),
    ]
)
