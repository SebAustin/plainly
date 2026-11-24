// swift-tools-version: 6.0
import PackageDescription

/// The privacy core of Plainly: redaction, routing and parsing.
/// Pure Swift with no Firebase dependency, so it is tested with `swift test`.
let package = Package(
  name: "PlainlyCore",
  platforms: [.iOS(.v18), .macOS(.v15)],
  products: [.library(name: "PlainlyCore", targets: ["PlainlyCore"])],
  targets: [
    .target(name: "PlainlyCore"),
    .testTarget(name: "PlainlyCoreTests", dependencies: ["PlainlyCore"]),
  ]
)
