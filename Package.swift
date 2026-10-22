// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "SuiBianCha",
    platforms: [.macOS(.v14)],
    products: [.executable(name: "Suibiancha", targets: ["Suibiancha"])],
    targets: [.executableTarget(name: "Suibiancha", path: "Sources/Suibiancha")]
)
