// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "VoiceRecorder",
    platforms: [
        .macOS(.v14)
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
                .headerSearchPath("../../Dependencies/whisper.cpp/ggml/include"),
                .headerSearchPath("../../Dependencies/ffmpeg-build/include"),
            ],
            linkerSettings: [
                .unsafeFlags([
                    "-L", "build",
                    "-L", "Dependencies/ffmpeg-build/lib",
                    "-L", "Dependencies/whisper.cpp/build/src",
                    "-L", "Dependencies/whisper.cpp/build/ggml/src",
                    "-L", "Dependencies/whisper.cpp/build/ggml/src/ggml-metal",
                    "-L", "Dependencies/whisper.cpp/build/ggml/src/ggml-blas",
                ]),
                .linkedLibrary("VoiceRecorderCore"),
                .linkedLibrary("whisper"),
                .linkedLibrary("ggml"),
                .linkedLibrary("ggml-base"),
                .linkedLibrary("ggml-cpu"),
                .linkedLibrary("ggml-metal"),
                .linkedLibrary("ggml-blas"),
                .linkedLibrary("avformat"),
                .linkedLibrary("avcodec"),
                .linkedLibrary("avutil"),
                .linkedLibrary("avdevice"),
                .linkedLibrary("avfilter"),
                .linkedLibrary("swresample"),
                .linkedLibrary("swscale"),
                .linkedLibrary("sqlite3"),
                .linkedLibrary("z"),
                .linkedLibrary("bz2"),
                .linkedLibrary("iconv"),
                .linkedFramework("Metal"),
                .linkedFramework("MetalKit"),
                .linkedFramework("Accelerate"),
                .linkedFramework("Foundation"),
                .linkedFramework("AVFoundation"),
                .linkedFramework("CoreMedia"),
                .linkedFramework("CoreAudio"),
                .linkedFramework("AudioToolbox"),
                .linkedFramework("CoreVideo"),
                .linkedFramework("VideoToolbox"),
                .linkedFramework("Security"),
                .linkedFramework("CoreServices"),
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
