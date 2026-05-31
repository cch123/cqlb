// swift-tools-version:5.10
import PackageDescription

let package = Package(
    name: "cqlb",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "CqlbCore", targets: ["CqlbCore"]),
        .library(name: "CqlbSettingsUI", targets: ["CqlbSettingsUI"]),
        .executable(name: "cqlb-query", targets: ["CqlbQuery"]),
        .executable(name: "cqlb-repl", targets: ["CqlbRepl"]),
        .executable(name: "cqlb-ime", targets: ["CqlbIME"]),
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
            name: "CqlbIME",
            dependencies: ["CqlbCore", "CqlbSettingsUI"],
            path: "Sources/CqlbIME",
            linkerSettings: [
                .linkedFramework("AppKit"),
                .linkedFramework("InputMethodKit"),
                .linkedFramework("Carbon"),
            ]
        ),
        .target(
            name: "CqlbSettingsUI",
            dependencies: ["CqlbCore"],
            path: "Sources/CqlbSettingsUI",
            linkerSettings: [
                .linkedFramework("AppKit"),
                .linkedFramework("SwiftUI"),
            ]
        ),
    ]
)
