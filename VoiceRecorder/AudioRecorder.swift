import AVFoundation
import SwiftUI
import ActivityKit

// MARK: - Audio Recorder (from working BrainPhArt patterns)

final class AudioRecorder: NSObject, ObservableObject, @unchecked Sendable {
    @Published var isRecording = false
    @Published var audioLevel: Float = 0.0
    @Published var recordingDuration: TimeInterval = 0

    private var audioEngine = AVAudioEngine()
    private var currentSessionId: String = ""

    private let bufferQueue = DispatchQueue(label: "com.brainphart.audioBuffer", qos: .userInitiated)
    private var audioBuffer: [Float] = []
    private var sampleRate: Double = 0
    private var chunkNumber: Int = 0
    private let chunkDuration: TimeInterval = 30.0

    private var consumerTask: Task<Void, Never>?
    private var shouldContinueProcessing = false
    private var recordingTimer: Timer?

    // Voice Activity Detection
    private let silenceThreshold: Float = 0.015
    private let maxSilenceDuration: Double = 0.8
    private var silenceSampleCount: Int = 0

    // Store last recording for transcription
    private var lastRecordingData: Data?

    override init() {
        super.init()
        print("[Recorder] Initialized")
    }

    // MARK: - Recording Control

    func startRecording(sessionId: String) async {
        currentSessionId = sessionId

        // iOS: Request permission and setup session
        let session = AVAudioSession.sharedInstance()
        do {
            try session.setCategory(.playAndRecord, mode: .default, options: [.defaultToSpeaker])
            try session.setActive(true)
        } catch {
            print("[Recorder] Failed to setup audio session: \(error)")
            return
        }

        // Check permission
        if await !checkMicrophonePermission() {
            print("[Recorder] Microphone permission denied")
            return
        }

        bufferQueue.sync {
            audioBuffer = []
            chunkNumber = 0
            silenceSampleCount = 0
        }

        setupAudioEngine()
        startConsumerTask()

        // Create session in database
        DatabaseManager.shared.createSession(id: sessionId)
    }

    private func checkMicrophonePermission() async -> Bool {
        let status = AVAudioApplication.shared.recordPermission
        switch status {
        case .granted:
            return true
        case .undetermined:
            return await withCheckedContinuation { continuation in
                AVAudioApplication.requestRecordPermission { granted in
                    continuation.resume(returning: granted)
                }
            }
        case .denied:
            return false
        @unknown default:
            return false
        }
    }

    func stopRecording() {
        print("[Recorder] Stopping")

        isRecording = false
        shouldContinueProcessing = false

        recordingTimer?.invalidate()
        recordingTimer = nil
        recordingDuration = 0

        if audioEngine.isRunning {
            audioEngine.inputNode.removeTap(onBus: 0)
            audioEngine.stop()
        }

        consumerTask?.cancel()
        consumerTask = nil

        // Get all remaining audio for transcription
        var allSamples: [Float] = []
        bufferQueue.sync {
            allSamples = audioBuffer
            audioBuffer = []
        }

        // Generate WAV and store for transcription
        if !allSamples.isEmpty {
            print("[Recorder] Storing recording: \(allSamples.count) samples")
            lastRecordingData = generateWAVData(samples: allSamples, sampleRate: sampleRate)

            // Also save to database
            _ = saveChunk(samples: allSamples, isFinal: true)
        }

        // Mark session complete
        if !currentSessionId.isEmpty {
            DatabaseManager.shared.completeSession(id: currentSessionId)
        }

        // IMPORTANT: Deactivate audio session so other apps can use mic
        do {
            try AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
            print("[Recorder] Audio session deactivated")
        } catch {
            print("[Recorder] Failed to deactivate audio session: \(error)")
        }

        print("[Recorder] Stopped")
        currentSessionId = ""
    }

    /// Get the last recording's audio data for transcription
    func getLastRecordingData() -> Data? {
        return lastRecordingData
    }

    // MARK: - Audio Engine Setup

    private func setupAudioEngine() {
        let inputNode = audioEngine.inputNode
        let format = inputNode.outputFormat(forBus: 0)

        sampleRate = format.sampleRate

        print("[Recorder] Format: \(format.sampleRate)Hz, \(format.channelCount)ch")

        inputNode.installTap(onBus: 0, bufferSize: 1024, format: format) { [weak self] buffer, _ in
            guard let self = self else { return }

            guard let channelData = buffer.floatChannelData else { return }
            let frameLength = Int(buffer.frameLength)
            let samples = Array(UnsafeBufferPointer(start: channelData[0], count: frameLength))

            // Calculate RMS for waveform visualization
            let sumOfSquares = samples.reduce(0) { $0 + $1 * $1 }
            let rms = sqrt(sumOfSquares / Float(samples.count))
            let level = min(1.0, rms * 12.0)

            Task { @MainActor [weak self] in
                self?.audioLevel = level
            }

            // Voice Activity Detection - skip extended silence
            let maxSilenceSamples = Int(self.maxSilenceDuration * self.sampleRate)

            self.bufferQueue.async {
                if rms < self.silenceThreshold {
                    self.silenceSampleCount += frameLength
                    if self.silenceSampleCount <= maxSilenceSamples {
                        self.audioBuffer.append(contentsOf: samples)
                    }
                } else {
                    self.silenceSampleCount = 0
                    self.audioBuffer.append(contentsOf: samples)
                }
            }
        }

        do {
            try audioEngine.start()
            shouldContinueProcessing = true
            Task { @MainActor [weak self] in
                self?.isRecording = true
                self?.recordingDuration = 0
                self?.recordingTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
                    guard let self = self, self.isRecording else { return }
                    Task { @MainActor in
                        self.recordingDuration += 1.0
                        // Update Live Activity with current duration
                        LiveActivityManager.shared.updateActivity(
                            duration: self.recordingDuration,
                            isRecording: true
                        )
                    }
                }
            }
            print("[Recorder] Started")
        } catch {
            print("[Recorder] Failed to start: \(error)")
        }
    }

    // MARK: - Chunk Processing

    private func startConsumerTask() {
        consumerTask = Task.detached { [weak self] in
            guard let self = self else { return }

            while self.shouldContinueProcessing {
                let samplesNeeded = Int(self.chunkDuration * self.sampleRate)

                var chunkSamples: [Float]?

                self.bufferQueue.sync {
                    if self.audioBuffer.count >= samplesNeeded {
                        chunkSamples = Array(self.audioBuffer.prefix(samplesNeeded))
                        self.audioBuffer.removeFirst(samplesNeeded)
                    }
                }

                if let samples = chunkSamples {
                    let success = self.saveChunk(samples: samples, isFinal: false)
                    if success {
                        self.chunkNumber += 1
                    }
                }

                try? await Task.sleep(for: .milliseconds(100))
            }
        }
    }

    private func saveChunk(samples: [Float], isFinal: Bool) -> Bool {
        let durationMs = Int(Double(samples.count) / sampleRate * 1000.0)
        let wavData = generateWAVData(samples: samples, sampleRate: sampleRate)

        DatabaseManager.shared.createChunk(
            sessionId: currentSessionId,
            chunkNumber: chunkNumber,
            audioData: wavData,
            durationMs: durationMs
        )

        let tag = isFinal ? " (FINAL)" : ""
        print("[Recorder] Chunk \(chunkNumber) saved: \(durationMs)ms\(tag)")

        return true
    }

    // MARK: - WAV Generation

    private func generateWAVData(samples: [Float], sampleRate: Double) -> Data {
        let sampleRateInt = Int32(sampleRate)
        let numChannels: Int16 = 1
        let bitsPerSample: Int16 = 16
        let bytesPerSample = Int16(bitsPerSample / 8)

        // Convert to 16-bit PCM
        let int16Samples = samples.map { sample in
            Int16(max(-1.0, min(1.0, sample)) * 32767.0)
        }

        var data = Data()

        // RIFF header
        data.append("RIFF".data(using: .ascii)!)
        data.append(withUnsafeBytes(of: UInt32(36 + int16Samples.count * 2).littleEndian) { Data($0) })
        data.append("WAVE".data(using: .ascii)!)

        // fmt chunk
        data.append("fmt ".data(using: .ascii)!)
        data.append(withUnsafeBytes(of: UInt32(16).littleEndian) { Data($0) })
        data.append(withUnsafeBytes(of: UInt16(1).littleEndian) { Data($0) }) // PCM
        data.append(withUnsafeBytes(of: numChannels.littleEndian) { Data($0) })
        data.append(withUnsafeBytes(of: sampleRateInt.littleEndian) { Data($0) })

        let byteRate = sampleRateInt * Int32(numChannels) * Int32(bytesPerSample)
        data.append(withUnsafeBytes(of: byteRate.littleEndian) { Data($0) })

        let blockAlign = numChannels * bytesPerSample
        data.append(withUnsafeBytes(of: blockAlign.littleEndian) { Data($0) })
        data.append(withUnsafeBytes(of: bitsPerSample.littleEndian) { Data($0) })

        // data chunk
        data.append("data".data(using: .ascii)!)
        data.append(withUnsafeBytes(of: UInt32(int16Samples.count * 2).littleEndian) { Data($0) })

        for sample in int16Samples {
            data.append(withUnsafeBytes(of: sample.littleEndian) { Data($0) })
        }

        return data
    }
}
