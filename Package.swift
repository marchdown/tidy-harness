// swift-tools-version: 6.0
import PackageDescription

// HarnessCore is PURE: Foundation only, no I/O beyond what callers hand it, no clock, no UI.
// A test (PurityTests) fails the build if that stops being true — a rule a machine can check.
let package = Package(
    name: "tidy-harness",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "HarnessCore", targets: ["HarnessCore"]),
        .executable(name: "harness", targets: ["harness"]),
    ],
    targets: [
        .target(name: "HarnessCore"),
        .executableTarget(name: "harness", dependencies: ["HarnessCore"]),
        .testTarget(name: "HarnessCoreTests", dependencies: ["HarnessCore"]),
    ]
)
