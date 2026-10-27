// swift-tools-version: 6.4
import PackageDescription

let package = Package(
    name: "ThermalPrinterCore",
    platforms: [.macOS(.v27), .iOS("26.4")],
    products: [
        .library(name: "ThermalPrinterCore", targets: ["ThermalPrinterCore"]),
        .executable(name: "thermal-pbm", targets: ["thermal-pbm"]),
    ],
    dependencies: [
        .package(url: "https://github.com/swiftlang/swift-markdown.git", branch: "release/6.4.x"),
    ],
    targets: [
        .target(
            name: "ThermalPrinterCore",
            dependencies: [.product(name: "Markdown", package: "swift-markdown")],
            path: "Sources/ThermalPrinterCore"
        ),
        .executableTarget(
            name: "thermal-pbm",
            dependencies: ["ThermalPrinterCore"],
            path: "Sources/thermal-pbm"
        ),
        .testTarget(
            name: "ThermalPrinterCoreTests",
            dependencies: ["ThermalPrinterCore"],
            path: "Tests/ThermalPrinterCoreTests",
            exclude: ["Image/Fixtures", "Sources/Fixtures"]
        ),
        .testTarget(
            name: "ThermalPrinterIntegrationTests",
            dependencies: ["ThermalPrinterCore"],
            path: "Tests/ThermalPrinterIntegrationTests"
        ),
    ]
)
