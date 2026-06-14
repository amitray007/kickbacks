// swift-tools-version:6.0
import PackageDescription

let package = Package(
  name: "KickbackBar",
  platforms: [.macOS(.v13)],
  targets: [
    // Testable logic (model DTO, CLI client, views) lives in the library; the
    // executable (added in Plan 4 Task 4) is a thin @main wrapper over it.
    .target(name: "KickbackKit"),
    .testTarget(name: "KickbackKitTests", dependencies: ["KickbackKit"]),
  ]
)
