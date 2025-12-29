import AppIntents
import SwiftUI

// MARK: - Start Recording Intent (Siri Shortcut)

@available(iOS 16.0, *)
struct StartRecordingIntent: AppIntent {
    static var title: LocalizedStringResource = "Start Voice Recording"
    static var description = IntentDescription("Start recording voice for transcription")

    // Opens the app when triggered
    static var openAppWhenRun: Bool = true

    func perform() async throws -> some IntentResult {
        // Post notification to start recording
        await MainActor.run {
            NotificationCenter.default.post(name: .startRecordingFromShortcut, object: nil)
        }
        return .result()
    }
}

// MARK: - Stop Recording Intent

@available(iOS 16.0, *)
struct StopRecordingIntent: AppIntent {
    static var title: LocalizedStringResource = "Stop Voice Recording"
    static var description = IntentDescription("Stop recording and transcribe")

    static var openAppWhenRun: Bool = true

    func perform() async throws -> some IntentResult {
        await MainActor.run {
            NotificationCenter.default.post(name: .toggleRecording, object: nil)
        }
        return .result()
    }
}

// MARK: - App Shortcuts Provider

@available(iOS 16.0, *)
struct VoiceRecorderShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: StartRecordingIntent(),
            phrases: [
                "Start recording with \(.applicationName)",
                "Record voice with \(.applicationName)",
                "Voice memo with \(.applicationName)",
                "Transcribe with \(.applicationName)"
            ],
            shortTitle: "Record Voice",
            systemImageName: "mic.fill"
        )

        AppShortcut(
            intent: StopRecordingIntent(),
            phrases: [
                "Stop recording with \(.applicationName)",
                "Stop \(.applicationName)"
            ],
            shortTitle: "Stop Recording",
            systemImageName: "stop.fill"
        )
    }
}

// Note: startRecordingFromShortcut notification is defined in VoiceRecorderApp.swift
