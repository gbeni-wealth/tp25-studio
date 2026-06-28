// swift-tools-version:6.0
// TP25Kit — shared core for TP25 Studio (iOS + macOS)
import PackageDescription

let package = Package(
    name: "TP25Kit",
    defaultLocalization: "en",
    platforms: [
        .iOS(.v17),
        .macOS(.v14),
    ],
    products: [
        .library(
            name: "TP25Kit",
            targets: [
                "BluetoothCore",
                "ProtocolEngine",
                "DeviceManager",
                "ThemeEngine",
                "PresetEngine",
                "CloudSync",
                "DeveloperTools",
                "SharedUI",
            ]
        ),
    ],
    targets: [
        // MARK: Core layers
        .target(name: "ProtocolEngine"),
        .target(name: "BluetoothCore"),
        .target(name: "DeviceManager", dependencies: ["BluetoothCore", "ProtocolEngine"]),
        .target(name: "ThemeEngine", dependencies: ["ProtocolEngine"]),
        .target(name: "PresetEngine", dependencies: ["ProtocolEngine", "ThemeEngine"]),
        .target(name: "CloudSync", dependencies: ["PresetEngine"]),
        .target(name: "DeveloperTools", dependencies: ["BluetoothCore", "ProtocolEngine"]),
        .target(name: "SharedUI", dependencies: ["DeviceManager", "ThemeEngine", "PresetEngine", "ProtocolEngine"]),

        // MARK: Tests
        .testTarget(name: "ProtocolEngineTests", dependencies: ["ProtocolEngine"]),
        .testTarget(name: "ThemeEngineTests", dependencies: ["ThemeEngine"]),
        .testTarget(name: "DeveloperToolsTests", dependencies: ["DeveloperTools", "BluetoothCore"]),
    ],
    swiftLanguageModes: [.v5] // Swift 6 toolchain; strict-concurrency migration tracked in README
)
