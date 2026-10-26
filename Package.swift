// swift-tools-version: 5.9
import PackageDescription

let package = Package(
  name: "SprintTracker",
  platforms: [.macOS(.v13)],
  products: [.executable(name: "SprintTracker", targets: ["SprintTracker"])],
  targets: [.executableTarget(name: "SprintTracker")]
)
