// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "MeetingCallerMac",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "MeetingCallerMac",
            path: "MeetingCallerMac",
            resources: [
                .process("Resources")
            ],
            linkerSettings: [
                .linkedFramework("CoreMediaIO"),
                .linkedFramework("AVFoundation"),
            ]
        )
    ]
)
