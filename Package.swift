// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "VoiceRecorder",
    platforms: [
        .macOS(.v13)
    ],
    targets: [
        // C++ core — headers exposed to bridge layer
        .systemLibrary(
            name: "CVoiceRecorderCore",
            pkgConfig: nil,
            providers: []
        ),

        // Obj-C++ bridge — connects Swift to C++ core
        .target(
            name: "VoiceRecorderBridge",
            dependencies: ["CVoiceRecorderCore"],
            path: "Sources/VoiceRecorderBridge",
            publicHeadersPath: ".",
            cxxSettings: [
                .headerSearchPath("../VoiceRecorderCore"),
                .headerSearchPath("../../Dependencies/whisper.cpp/include"),
                .headerSearchPath("../../Dependencies/ffmpeg-build/include"),
            ],
            linkerSettings: [
                .linkedLibrary("VoiceRecorderCore"),
                .linkedLibrary("whisper"),
                .linkedLibrary("ggml"),
                .linkedLibrary("avformat"),
                .linkedLibrary("avcodec"),
                .linkedLibrary("avutil"),
                .linkedLibrary("avdevice"),
                .linkedLibrary("swresample"),
                .linkedLibrary("sqlite3"),
                .linkedFramework("Metal"),
                .linkedFramework("MetalKit"),
                .linkedFramework("Accelerate"),
                .linkedFramework("AVFoundation"),
                .linkedFramework("CoreMedia"),
                .linkedFramework("CoreAudio"),
                .linkedFramework("AudioToolbox"),
            ]
        ),

        // SwiftUI app
        .executableTarget(
            name: "VoiceRecorder",
            dependencies: ["VoiceRecorderBridge"],
            path: "Sources/VoiceRecorder",
            swiftSettings: [
                .define("MACOS_BUILD"),
            ]
        ),
    ],
    cxxLanguageStandard: .cxx17
)
