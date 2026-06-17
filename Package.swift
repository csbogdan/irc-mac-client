// swift-tools-version:5.9
import PackageDescription

// Builds the library + tests from the command line (`swift build`, `swift test`).
// To run the GUI, create a macOS App target in Xcode and add Sources/ (see README).
let package = Package(
    name: "RelayIRC",
    platforms: [.macOS(.v14)],
    targets: [
        .target(
            name: "RelayIRC",
            path: "Sources",
            exclude: ["App/RelayApp.swift"]   // @main app entry lives in the Xcode app target
        ),
        .testTarget(
            name: "RelayIRCTests",
            dependencies: ["RelayIRC"],
            path: "Tests"
        ),
    ]
)
