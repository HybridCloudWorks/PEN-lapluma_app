// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "ApertureKit",
    defaultLocalization: "en",
    platforms: [.iOS(.v18), .macOS(.v15)],
    products: [
        .library(name: "ApertureDomain", targets: ["ApertureDomain"]),
        .library(name: "ApertureAPI", targets: ["ApertureAPI"]),
        .library(name: "ApertureUI", targets: ["ApertureUI"]),
        .executable(name: "LaPlumaWorkforce", targets: ["LaPlumaWorkforce"])
    ],
    // No third-party dependencies. This is deliberate and enforced:
    // ADR-012 forbids third-party SDKs in the client. Adding one requires
    // Security approval and updates to the SBOM gate.
    dependencies: [],
    targets: [
        .target(name: "ApertureDomain"),
        .target(name: "ApertureAPI", dependencies: ["ApertureDomain"]),
        .target(
            name: "ApertureUI",
            dependencies: ["ApertureDomain", "ApertureAPI"],
            resources: [.process("Resources")]
        ),
        .executableTarget(
            name: "LaPlumaWorkforce",
            dependencies: ["ApertureDomain", "ApertureAPI", "ApertureUI"]
        ),
        .testTarget(name: "ApertureKitTests", dependencies: ["ApertureDomain", "ApertureAPI", "ApertureUI"])
    ],
    swiftLanguageModes: [.v6]
)
