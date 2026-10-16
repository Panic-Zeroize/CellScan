// swift-tools-version:5.9
// Test harness for CellScan's platform-independent core (CellScan/Core).
// The iOS app itself is built from CellScan.xcodeproj; this package only exists
// so the model, CSV and persistence logic can be compiled and stress-tested
// with `swift test` on macOS or Linux (no simulator needed).
import PackageDescription

let package = Package(
    name: "CellScanCore",
    targets: [
        .target(
            name: "CellScanCore",
            path: "CellScan/Core"
        ),
        .testTarget(
            name: "CellScanCoreTests",
            dependencies: ["CellScanCore"],
            path: "Tests/CellScanCoreTests"
        ),
    ]
)
