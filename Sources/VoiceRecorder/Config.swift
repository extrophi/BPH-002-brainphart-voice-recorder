//
//  Config.swift
//  VoiceRecorder
//
//  Single source of truth for all configurable values.
//  No hardcoded paths, names, or magic numbers anywhere else.
//

import Foundation
import os.log

// MARK: - Logging

/// Unified logger for the entire app. Use instead of print() or NSLog().
let log = Logger(subsystem: Bundle.main.bundleIdentifier ?? "art.brainph.voice",
                 category: "BrainPhartVoice")

// MARK: - Configuration

enum Config {
    // MARK: Whisper Model

    /// Model file name without extension.
    static let whisperModelName = "ggml-base.en"

    /// Model file extension.
    static let whisperModelExtension = "bin"

    /// Full model filename.
    static var whisperModelFilename: String {
        "\(whisperModelName).\(whisperModelExtension)"
    }

    /// Resolves the model path dynamically from bundle or project tree.
    /// Returns nil if model cannot be found.
    static func resolveModelPath() -> String? {
        var candidates: [String] = [
            // Bundled in .app/Contents/Resources/
            Bundle.main.path(forResource: whisperModelName, ofType: whisperModelExtension),
            // .app/Contents/Resources/models/
            Bundle.main.resourceURL?
                .appendingPathComponent("models")
                .appendingPathComponent(whisperModelFilename).path,
            // Development: project root Resources/models/
            Bundle.main.bundleURL
                .deletingLastPathComponent()
                .appendingPathComponent("Resources/models")
                .appendingPathComponent(whisperModelFilename).path
        ].compactMap { $0 }

        // When running from .build/release/ the executable is several levels
        // deep inside the project. Walk up from the executable to find the
        // project root's Resources/models/ directory.
        let execURL = URL(fileURLWithPath: ProcessInfo.processInfo.arguments[0])
            .resolvingSymlinksInPath()
        var dir = execURL.deletingLastPathComponent()
        for _ in 0..<6 {
            let candidate = dir
                .appendingPathComponent("Resources/models")
                .appendingPathComponent(whisperModelFilename).path
            candidates.append(candidate)
            dir = dir.deletingLastPathComponent()
        }

        // Also check current working directory.
        let cwd = FileManager.default.currentDirectoryPath
        candidates.append(cwd + "/Resources/models/" + whisperModelFilename)

        log.info("Searching \(candidates.count) candidate paths for whisper model...")
        for (i, path) in candidates.enumerated() {
            let exists = FileManager.default.fileExists(atPath: path)
            if exists {
                log.info("  [\(i)] FOUND: \(path)")
                return path
            }
        }

        log.error("Whisper model not found after searching \(candidates.count) paths.")
        for (i, path) in candidates.enumerated() {
            log.error("  [\(i)] \(path)")
        }
        return nil
    }

    // MARK: Storage

    /// Application support directory for persistent data.
    /// Resolved dynamically via FileManager — works in sandbox and non-sandbox.
    static var applicationSupportDirectory: URL {
        let fm = FileManager.default
        let appSupport = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let dir = appSupport.appendingPathComponent("VoiceRecorder")
        if !fm.fileExists(atPath: dir.path) {
            try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
        }
        return dir
    }

    /// SQLite database path.
    static var databasePath: String {
        applicationSupportDirectory.appendingPathComponent("voicerecorder.db").path
    }

    // MARK: Audio

    /// Transcription sample rate (whisper.cpp requirement).
    static let transcriptionSampleRate: Int = 16000

    /// Minimum audio duration (seconds) required for transcription.
    /// Whisper produces 0 segments for very short audio (< ~1s), so skip those.
    static let minimumTranscriptionDuration: Float = 1.0

    /// Maximum burst length in seconds before flushing to disk.
    static let burstLengthSeconds: Int = 35

    /// Metering poll interval in seconds.
    static let meteringPollInterval: TimeInterval = 0.05

    // MARK: Audio Levels

    /// Number of metering samples to keep for waveform display.
    static let meteringSampleCount: Int = 100
}
