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
let log = Logger(subsystem: Bundle.main.bundleIdentifier ?? "com.voicerecorder.app",
                 category: "VoiceRecorder")

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
        let candidates: [String] = [
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

        for path in candidates where FileManager.default.fileExists(atPath: path) {
            return path
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

    /// Recording sample rate (high quality, preserved in DB).
    static let recordingSampleRate: Int = 44100

    /// Transcription sample rate (whisper.cpp requirement).
    static let transcriptionSampleRate: Int = 16000

    /// Maximum burst length in seconds before flushing to disk.
    static let burstLengthSeconds: Int = 35

    /// Metering poll interval in seconds.
    static let meteringPollInterval: TimeInterval = 0.05

    // MARK: Audio Levels

    /// Number of metering samples to keep for waveform display.
    static let meteringSampleCount: Int = 100
}
