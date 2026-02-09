//
//  AppState.swift
//  VoiceRecorder
//
//  Observable state management for the entire app.
//
//  Owns the bridge objects (WhisperBridge, StorageBridge) and AudioManager,
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
import VoiceRecorderBridge

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

    /// Whether the whisper model was successfully loaded.
    var isModelLoaded = false

    /// Global error message — set by any component when something fails.
    /// The UI displays this in both the floating overlay and the main window.
    /// Auto-dismisses after 5 seconds.
    var errorMessage: String?

    /// Timestamp of the most recent error.
    var lastError: Date?

    // MARK: - Bridges & Audio

    let whisperBridge = WhisperBridge()
    let storageBridge = StorageBridge(databasePath: Config.databasePath)
    let audioManager = AudioManager()

    // MARK: - Private

    /// Timer that polls metering level every 50ms during recording.
    private var meteringTimer: Timer?

    /// Timer that increments the elapsed-seconds counter every second.
    private var elapsedTimer: Timer?

    /// Timer that auto-dismisses error messages.
    private var errorDismissTimer: Timer?

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

    // MARK: - Error Handling

    /// Set a visible error message. Auto-dismisses after 5 seconds.
    func setError(_ message: String) {
        log.error("\(message)")
        errorMessage = message
        lastError = Date()

        // Cancel any existing dismiss timer.
        errorDismissTimer?.invalidate()
        errorDismissTimer = Timer.scheduledTimer(withTimeInterval: 5.0, repeats: false) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.dismissError()
            }
        }
    }

    /// Dismiss the current error message.
    func dismissError() {
        errorMessage = nil
        errorDismissTimer?.invalidate()
        errorDismissTimer = nil
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
        if sessionId.isEmpty {
            setError("Failed to create recording session in database")
            return
        }
        activeSessionId = sessionId

        // Wire up the chunk callback so each 35-second PCM chunk is
        // persisted immediately. Note: this fires asynchronously during recording
        // for intermediate chunks. The final flush chunk is stored synchronously
        // in stopRecording() to avoid race conditions.
        audioManager.onChunkComplete = { [weak self] pcmData, chunkIndex in
            Task { @MainActor [weak self] in
                guard let self, let sid = self.activeSessionId else {
                    log.warning("Chunk \(chunkIndex) callback fired but no active session")
                    return
                }
                let ok = self.storageBridge.addChunk(pcmData, toSession: sid, at: chunkIndex)
                if ok {
                    log.info("Stored intermediate chunk \(chunkIndex): \(pcmData.count) bytes")
                } else {
                    log.error("FAILED to store chunk \(chunkIndex): \(pcmData.count) bytes for session \(sid)")
                    self.setError("Failed to save audio chunk — storage error")
                }
            }
        }

        guard audioManager.startRecording() else {
            setError("Failed to start audio engine — check microphone access")
            activeSessionId = nil
            return
        }

        isRecording = true
        recordingElapsedSeconds = 0
        startMeteringPolling()
        startElapsedTimer()
    }

    /// Stop the current recording and begin transcription.
    func stopRecording() {
        guard isRecording else { return }

        // Stop engine and get the final flush chunk synchronously.
        // CRITICAL: We must store this BEFORE calling transcribeActiveSession(),
        // otherwise the chunk callback's async Task hasn't run yet and the
        // database has zero chunks for short recordings.
        let finalChunk = audioManager.stopRecording()

        isRecording = false
        stopMeteringPolling()
        stopElapsedTimer()
        currentMeteringLevel = 0
        meteringSamples = Array(repeating: 0, count: Config.meteringSampleCount)

        // Store the final flush chunk synchronously.
        if let (data, idx) = finalChunk, let sid = activeSessionId {
            log.info("Storing final chunk \(idx): \(data.count) bytes for session \(sid)")
            let stored = storageBridge.addChunk(data, toSession: sid, at: idx)
            if !stored {
                log.error("FAILED to store final chunk \(idx) for session \(sid)")
                setError("Failed to save final audio chunk — recording may be lost")
                activeSessionId = nil
                loadSessions()
                return
            }
        } else if finalChunk == nil {
            log.warning("No final chunk data — recording may have been too short or mic was silent")
        }

        // Begin transcription — now all chunks are in the database.
        transcribeActiveSession()
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
    /// New flow: chunks are raw 16kHz mono PCM — concatenate them directly,
    /// write as a WAV file, then feed to WhisperBridge.
    private func transcribeActiveSession() {
        guard let sessionId = activeSessionId else {
            setError("No active session to transcribe")
            return
        }

        // Check if model is loaded before attempting transcription.
        if !whisperBridge.isModelLoaded() {
            setError("Whisper model not loaded — transcription unavailable")
            isTranscribing = false
            loadSessions()
            return
        }

        isTranscribing = true
        transcriptionProgress = 0

        // Get raw PCM data (concatenated chunks) from the database.
        guard let pcmData = storageBridge.getAudioForSession(sessionId) else {
            setError("No audio data found for session — cannot transcribe")
            isTranscribing = false
            loadSessions()
            return
        }

        if pcmData.count == 0 {
            setError("Audio data is empty — cannot transcribe")
            isTranscribing = false
            loadSessions()
            return
        }

        // Validate PCM data: each sample is 4 bytes (Float32), at 16kHz.
        let sampleCount = pcmData.count / MemoryLayout<Float>.size
        let durationSeconds = Float(sampleCount) / Float(Config.transcriptionSampleRate)
        log.info("Transcribing session \(sessionId): \(pcmData.count) bytes, \(sampleCount) samples, ~\(String(format: "%.1f", durationSeconds))s of audio")

        if durationSeconds < Config.minimumTranscriptionDuration {
            log.warning("Audio too short for transcription: \(String(format: "%.1f", durationSeconds))s (\(sampleCount) samples) — skipping")
            isTranscribing = false
            activeSessionId = nil
            loadSessions()
            return
        }

        // Feed raw PCM directly to WhisperBridge — no file I/O or conversion needed.
        whisperBridge.transcribePCMData(
            pcmData,
            sampleRate: Int32(Config.transcriptionSampleRate),
            progress: { [weak self] progress in
                Task { @MainActor [weak self] in
                    self?.transcriptionProgress = progress
                }
            },
            completion: { [weak self] transcript, error in
                Task { @MainActor [weak self] in
                    guard let self else { return }
                    self.isTranscribing = false
                    self.transcriptionProgress = 0

                    if let transcript, !transcript.isEmpty, error == nil {
                        self.storageBridge.updateTranscript(transcript, forSession: sessionId)
                        self.storageBridge.completeSession(sessionId, withDuration: self.recordingElapsedSeconds * 1000)
                        self.latestTranscript = transcript

                        // Auto-paste the transcription to the user's cursor.
                        AutoPaste.pasteText(transcript)
                    } else {
                        let msg = error?.localizedDescription ?? "Unknown transcription error"
                        self.setError("Transcription failed: \(msg)")
                        log.error("Transcription failed for session \(sessionId): \(msg)")
                    }

                    self.activeSessionId = nil
                    self.loadSessions()
                }
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
                let rawLevel = self.audioManager.getMeteringLevel()

                // Amplify the metering level dramatically.
                // Raw RMS levels are typically 0.0-0.1 for normal speech.
                // Use aggressive power curve + high multiplier so bars FILL during speech.
                let amplified = min(pow(rawLevel, 0.3) * 5.0, 1.0)

                self.currentMeteringLevel = amplified

                // Shift samples left and append the new value.
                self.meteringSamples.removeFirst()
                self.meteringSamples.append(amplified)
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

    // MARK: - Shutdown

    /// Clean up all resources before process exit.
    /// Must be called from applicationWillTerminate to avoid a crash in
    /// ggml_metal_rsets_free when C++ static destructors race with Metal's
    /// residency-set background thread.
    func cleanup() {
        if isRecording {
            _ = audioManager.stopRecording()
            isRecording = false
        }
        whisperBridge.shutdown()
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
