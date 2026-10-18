// swift-tools-version: 6.0
import PackageDescription
let package = Package(name: "FocusIsland", platforms: [.macOS(.v14)], products: [.executable(name: "FocusIsland", targets: ["FocusIsland"])], targets: [.target(name: "FocusCore"), .executableTarget(name: "FocusIsland", dependencies: ["FocusCore"], resources: [.process("Resources")]), .executableTarget(name: "FocusCoreChecks", dependencies: ["FocusCore"], path: "Tests/FocusCoreTests")])
