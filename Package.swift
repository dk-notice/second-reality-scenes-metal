// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "SRMetal",
    platforms: [.macOS("15.0")],
    targets: [
        // libopenmpt (tracker music), built from ThirdParty/libopenmpt by build.sh as a static
        // library in build/libopenmpt/src/bin. Run ./build.sh at least once before `swift build`.
        .systemLibrary(name: "COpenMPT", path: "Sources/COpenMPT"),
        .executableTarget(
            name: "SRMetal",
            dependencies: ["COpenMPT"],
            path: "Sources/SRMetal",
            linkerSettings: [
                .unsafeFlags(["-L", Context.packageDirectory + "/build/libopenmpt/src/bin"])
            ]
        )
    ]
)
