// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "IPTVPlayer",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(
            name: "IPTVPlayer",
            targets: ["IPTVPlayer"]
        )
    ],
    dependencies: [],
    targets: [
        // Plays the Matroska/AVI/FLV containers AVFoundation cannot demux, which
        // covers roughly half of a typical Xtream VOD catalogue. Live TV stays on
        // AVPlayer. Run scripts/fetch_vlckit.sh to populate vendor/.
        .binaryTarget(
            name: "VLCKit",
            path: "vendor/VLCKit.xcframework"
        ),
        // Reaches libVLC's subtitle text-renderer setter, which VLCKit does not
        // surface publicly. Objective-C because it needs the private
        // `playerInstance` handle.
        .target(
            name: "VLCBridge",
            dependencies: ["VLCKit"],
            path: "VLCBridge",
            publicHeadersPath: "include"
        ),
        .executableTarget(
            name: "IPTVPlayer",
            dependencies: ["VLCKit", "VLCBridge"],
            path: "IPTVPlayer",
            exclude: ["Info.plist", "IPTVPlayer.entitlements", "Assets.xcassets"],
            sources: [
                "App",
                "Models",
                "Services",
                "ViewModels",
                "Views"
            ]
        )
    ]
)
