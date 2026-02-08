//
//  AppState.swift
//  VoiceRecorder
//
//  Observable state management for the entire app.
//
//  Owns the three bridge objects (WhisperBridge, AudioBridge, StorageBridge),
//  drives recording/transcription lifecycle, and exposes all state that the
//  UI layer needs.
//
//  Threading contract:
//  - All published properties are mutated on @MainActor.
//  - Bridge callbacks are dispatched to the main queue by the Obj-C++ layer.
//

import SwiftUI
import AppKit
import Combine

@MainActor
@Observable
final class AppState {

    // MARK: - Published State

    /// Whether the microphone is actively capturing audio.
    var isRecording = false

    /// Whether whisper.cpp is currently transcribing audio.
    var isTranscribing = false

    /// Transcription progress from 0.0 to 1.0.
    var transcriptionProgress: Float = 0

    /// Current audio input level (0.0 -- 1.0), polled during recording.
    var currentMeteringLevel: Float = 0

    /// All persisted recording sessions, newest first.
    var sessions: [VRSession] = []

    /// The most recent transcription result (used for auto-paste).
    var latestTranscript: String?

    /// Circular buffer of recent metering samples for the waveform view.
    var meteringSamples: [Float] = Array(repeating: 0, count: Config.meteringSampleCount)

    /// Elapsed seconds in the current recording.
    var recordingElapsedSeconds: Int = 0

    // MARK: - Bridges

    let whisperBridge = WhisperBridge()
    let audioBridge = AudioBridge()
    let storageBridge = StorageBridge(databasePath: Config.databasePath)

    // MARK: - Private

    /// Timer that polls metering level every 50ms during recording.
    private var meteringTimer: Timer?

    /// Timer that increments the elapsed-seconds counter every second.
    private var elapsedTimer: Timer?

    /// The active session id created when recording starts.
    private var activeSessionId: String?

    /// Cancellable for the toggle-recording notification from menu bar.
    private var toggleCancellable: Any?

    /// Reference to the floating overlay controller.
    private var floatingController: FloatingPanelController?

    // MARK: - Init

    init() {
        loadSessions()
        observeToggleNotification()
    }

    // MARK: - Floating Overlay

    /// Creates and shows the floating overlay panel.
    func showFloatingOverlay() {
        guard floatingController == nil else { return }
        let controller = FloatingPanelController(appState: self)
        controller.showWindow(nil)
        floatingController = controller
    }

    // MARK: - Recording Lifecycle

    /// Start a new recording session.
    func startRecording() {
        guard !isRecording else { return }

        // Create a new session in the database.
        let sessionId = storageBridge.createSession()
        activeSessionId = sessionId

        // Wire up the burst-chunk callback so each 35-second chunk is
        // persisted immediately.
        audioBridge.onChunkComplete = { [weak self] chunkPath, chunkIndex, durationMs in
            guard let self, let sid = self.activeSessionId else { return }
            self.storageBridge.addChunk(sid,
                                        chunkIndex: chunkIndex,
                                        audioPath: chunkPath,
                                        durationMs: durationMs)
        }

        audioBridge.startRecording()

        isRecording = true
        recordingElapsedSeconds = 0
        startMeteringPolling()
        startElapsedTimer()
    }

    /// Stop the current recording and begin transcription.
    func stopRecording() {
        guard isRecording else { return }

        audioBridge.stopRecording { [weak self] finalChunkPath, finalDurationMs in
            guard let self else { return }

            // Persist the final partial chunk.
            if let sid = self.activeSessionId,
               let path = finalChunkPath {
                let lastIndex = Int32(self.storageBridge.chunkCount(forSession: sid))
                self.storageBridge.addChunk(sid,
                                            chunkIndex: lastIndex,
                                            audioPath: path,
                                            durationMs: finalDurationMs)
            }

            self.isRecording = false
            self.stopMeteringPolling()
            self.stopElapsedTimer()
            self.currentMeteringLevel = 0
            self.meteringSamples = Array(repeating: 0, count: Config.meteringSampleCount)

            // Begin transcription.
            self.transcribeActiveSession()
        }
    }

    /// Toggle between recording and stopped.
    func toggleRecording() {
        if isRecording {
            stopRecording()
        } else {
            startRecording()
        }
    }

    // MARK: - Transcription

    /// Transcribe all chunks for the currently active session.
    private func transcribeActiveSession() {
        guard let sessionId = activeSessionId else { return }

        isTranscribing = true
        transcriptionProgress = 0
        storageBridge.updateStatus(sessionId, status: "transcribing")

        // Retrieve the concatenated audio file for the session.
        guard let audioPath = storageBridge.getAudioForSession(sessionId) else {
            isTranscribing = false
            storageBridge.updateStatus(sessionId, status: "failed")
            loadSessions()
            return
        }

        whisperBridge.transcribeAudio(
            atPath: audioPath,
            sampleRate: 16000,
            progress: { [weak self] progress in
                self?.transcriptionProgress = progress
            },
            completion: { [weak self] transcript, error in
                guard let self else { return }
                self.isTranscribing = false
                self.transcriptionProgress = 0

                if let transcript, error == nil {
                    self.storageBridge.updateTranscript(sessionId, transcript: transcript)
                    self.storageBridge.completeSession(sessionId)
                    self.latestTranscript = transcript

                    // Auto-paste the transcription to the user's cursor.
                    AutoPaste.pasteText(transcript)
                } else {
                    self.storageBridge.updateStatus(sessionId, status: "failed")
                    if let error {
                        log.error("Transcription failed: \(error.localizedDescription)")
                    }
                }

                self.activeSessionId = nil
                self.loadSessions()
            }
        )
    }

    /// Retry transcription for a previously failed (or any) session.
    func retryTranscription(sessionId: String) {
        activeSessionId = sessionId
        transcribeActiveSession()
    }

    // MARK: - Session Management

    /// Reload all sessions from the database, sorted newest-first.
    func loadSessions() {
        if let all = storageBridge.getAllSessions() as? [VRSession] {
            sessions = all.sorted {
                $0.createdAt > $1.createdAt
            }
        }
    }

    /// Delete a session and all its associated audio chunks.
    func deleteSession(sessionId: String) {
        storageBridge.deleteSession(sessionId)
        loadSessions()
    }

    // MARK: - Metering

    private func startMeteringPolling() {
        meteringTimer = Timer.scheduledTimer(withTimeInterval: Config.meteringPollInterval, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self, self.isRecording else { return }
                let level = self.audioBridge.currentMeteringLevel
                self.currentMeteringLevel = level

                // Shift samples left and append the new value.
                self.meteringSamples.removeFirst()
                self.meteringSamples.append(level)
            }
        }
    }

    private func stopMeteringPolling() {
        meteringTimer?.invalidate()
        meteringTimer = nil
    }

    // MARK: - Elapsed Timer

    private func startElapsedTimer() {
        elapsedTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self, self.isRecording else { return }
                self.recordingElapsedSeconds += 1
            }
        }
    }

    private func stopElapsedTimer() {
        elapsedTimer?.invalidate()
        elapsedTimer = nil
    }

    // MARK: - Notification Observer

    /// Listen for toggle-recording requests from the menu-bar item.
    private func observeToggleNotification() {
        toggleCancellable = NotificationCenter.default.addObserver(
            forName: .toggleRecordingAction,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.toggleRecording()
            }
        }
    }
}
