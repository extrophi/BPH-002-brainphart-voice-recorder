import Foundation
@preconcurrency import SwiftWhisper
import AVFoundation

// MARK: - Transcription Manager

actor TranscriptionManager {
    static let shared = TranscriptionManager()

    private var whisper: Whisper?
    private var isLoading = false
    private var currentModelName: String = "base"

    private init() {}

    // MARK: - Model Loading

    func loadModel(name: String = "base") async throws {
        guard whisper == nil, !isLoading else { return }
        isLoading = true

        let modelPath = getModelPath(name: name)

        guard FileManager.default.fileExists(atPath: modelPath.path) else {
            isLoading = false
            throw TranscriptionError.modelNotFound(modelPath.path)
        }

        print("Loading Whisper model: \(name)")

        let params = WhisperParams(strategy: .beamSearch)
        params.language = .english

        whisper = Whisper(fromFileURL: modelPath, withParams: params)
        currentModelName = name

        isLoading = false
        print("Whisper model loaded: \(name)")
    }

    private func getModelPath(name: String) -> URL {
        #if os(macOS)
        return FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("brainphart/models/ggml-\(name).bin")
        #else
        // iOS: Use app documents directory
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        return docs.appendingPathComponent("models/ggml-\(name).bin")
        #endif
    }

    // MARK: - Transcription

    func transcribe(audioData: Data) async throws -> String {
        if whisper == nil {
            try await loadModel()
        }

        guard let whisper = whisper else {
            throw TranscriptionError.modelNotLoaded
        }

        // Resample to 16kHz
        let audioFrames = try await resampleTo16kHz(audioData)

        print("Transcribing \(audioFrames.count) samples...")

        let segments = try await whisper.transcribe(audioFrames: audioFrames)

        let transcript = segments
            .map { $0.text }
            .joined(separator: " ")
            .trimmingCharacters(in: .whitespaces)

        print("Transcribed: \(transcript.prefix(50))...")

        return transcript
    }

    func transcribe(audioURL: URL) async throws -> String {
        let data = try Data(contentsOf: audioURL)
        return try await transcribe(audioData: data)
    }

    // MARK: - Audio Resampling

    private func resampleTo16kHz(_ wavData: Data) async throws -> [Float] {
        // Write to temp file
        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("wav")

        try wavData.write(to: tempURL)
        defer {
            try? FileManager.default.removeItem(at: tempURL)
        }

        // Resample using AVAudioFile
        let sourceFile = try AVAudioFile(forReading: tempURL)
        let sourceFormat = sourceFile.processingFormat
        let sourceSampleRate = sourceFormat.sampleRate

        guard let targetFormat = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: 16000,
            channels: 1,
            interleaved: false
        ) else {
            throw TranscriptionError.formatError
        }

        guard let converter = AVAudioConverter(from: sourceFormat, to: targetFormat) else {
            throw TranscriptionError.converterError
        }

        let frameCount = AVAudioFrameCount(sourceFile.length)
        guard let sourceBuffer = AVAudioPCMBuffer(pcmFormat: sourceFormat, frameCapacity: frameCount) else {
            throw TranscriptionError.bufferError
        }

        try sourceFile.read(into: sourceBuffer)

        let ratio = 16000.0 / sourceSampleRate
        let targetFrameCount = AVAudioFrameCount(Double(frameCount) * ratio)

        guard let targetBuffer = AVAudioPCMBuffer(pcmFormat: targetFormat, frameCapacity: targetFrameCount) else {
            throw TranscriptionError.bufferError
        }

        var error: NSError?
        converter.convert(to: targetBuffer, error: &error) { _, outStatus in
            outStatus.pointee = .haveData
            return sourceBuffer
        }

        if let error = error {
            throw TranscriptionError.conversionFailed(error.localizedDescription)
        }

        guard let channelData = targetBuffer.floatChannelData else {
            throw TranscriptionError.noChannelData
        }

        return Array(UnsafeBufferPointer(start: channelData[0], count: Int(targetBuffer.frameLength)))
    }

    // MARK: - Model Management

    func getCurrentModel() -> String {
        return currentModelName
    }

    func availableModels() -> [String] {
        return ["tiny", "base", "small", "medium", "large"]
    }

    func switchModel(to name: String) async throws {
        whisper = nil
        try await loadModel(name: name)
    }
}

// MARK: - Transcription Worker

actor TranscriptionWorker {
    static let shared = TranscriptionWorker()

    private var isRunning = false
    private let checkInterval: TimeInterval = 2.0

    private init() {}

    func start() async {
        guard !isRunning else { return }
        isRunning = true

        print("Transcription worker started")

        while isRunning {
            await processNextChunk()
            try? await Task.sleep(for: .seconds(checkInterval))
        }
    }

    func stop() {
        isRunning = false
        print("Transcription worker stopped")
    }

    func processNow() async {
        await processNextChunk()
    }

    private func processNextChunk() async {
        // Get pending chunks
        let pendingChunks = DatabaseManager.shared.getPendingChunks()

        for chunk in pendingChunks {
            print("Processing chunk \(chunk.id) for session \(chunk.sessionId)")

            // Mark as processing
            DatabaseManager.shared.updateChunkStatus(chunkId: chunk.id, status: "processing")

            do {
                // Transcribe
                let transcript = try await TranscriptionManager.shared.transcribe(audioData: chunk.audioData)

                // Save transcript
                DatabaseManager.shared.saveChunkTranscript(
                    sessionId: chunk.sessionId,
                    chunkNumber: chunk.chunkNumber,
                    transcript: transcript
                )

                // Mark complete
                DatabaseManager.shared.updateChunkStatus(chunkId: chunk.id, status: "complete")

                // Notify UI
                await MainActor.run {
                    NotificationCenter.default.post(
                        name: .transcriptionComplete,
                        object: chunk.sessionId
                    )
                }

                print("Chunk \(chunk.id) transcribed successfully")

            } catch {
                print("Transcription failed for chunk \(chunk.id): \(error)")
                DatabaseManager.shared.updateChunkStatus(chunkId: chunk.id, status: "failed")
            }
        }
    }
}

// MARK: - Chunk Model

struct PendingChunk {
    let id: String
    let sessionId: String
    let chunkNumber: Int
    let audioData: Data
}

// MARK: - Errors

enum TranscriptionError: Error, LocalizedError {
    case modelNotFound(String)
    case modelNotLoaded
    case formatError
    case converterError
    case bufferError
    case conversionFailed(String)
    case noChannelData

    var errorDescription: String? {
        switch self {
        case .modelNotFound(let path):
            return "Whisper model not found at: \(path)"
        case .modelNotLoaded:
            return "Whisper model not loaded"
        case .formatError:
            return "Failed to create audio format"
        case .converterError:
            return "Failed to create audio converter"
        case .bufferError:
            return "Failed to create audio buffer"
        case .conversionFailed(let message):
            return "Audio conversion failed: \(message)"
        case .noChannelData:
            return "No channel data in buffer"
        }
    }
}
