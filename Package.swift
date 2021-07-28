// swift-tools-version:5.3

import PackageDescription

let package = Package(
  name: "lzfse",
  platforms: [.macOS(.v10_11)],
  dependencies: [
    .package(url: "https://github.com/apple/swift-argument-parser", .upToNextMinor(from: "0.4.0"))
  ],
  targets: [
    .target(
      name: "lzfse",
      dependencies: [.product(name: "ArgumentParser", package: "swift-argument-parser")])
  ]
)
