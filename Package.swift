// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "OpenShelf",
    platforms: [.macOS(.v14)],
    products: [.executable(name: "OpenShelf", targets: ["OpenShelf"])],
    dependencies: [.package(url: "https://github.com/sparkle-project/Sparkle", exact: "2.9.6")],
    targets: [
        .executableTarget(name: "OpenShelf", dependencies: [.product(name: "Sparkle", package: "Sparkle")], linkerSettings: [.unsafeFlags(["-Xlinker", "-rpath", "-Xlinker", "@executable_path/../Frameworks"])]),
        .testTarget(name: "OpenShelfTests", dependencies: ["OpenShelf"])
    ]
)
