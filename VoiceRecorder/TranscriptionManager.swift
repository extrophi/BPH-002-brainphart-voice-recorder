import Foundation
import AVFoundation

// MARK: - Transcription Manager (WhisperKit)
// WhisperKit works in simulator with CPU-only mode

#if canImport(WhisperKit)
import WhisperKit

// MARK: - Loading State
enum TranscriptionLoadingState: Sendable {
    case idle
    case downloading
    case loading
    case ready
    case error(String)

    var description: String {
        switch self {
        case .idle: return "Not loaded"
        case .downloading: return "Downloading model..."
        case .loading: return "Loading model..."
        case .ready: return "Ready"
        case .error(let msg): return "Error: \(msg)"
        }
    }

    var isLoading: Bool {
        switch self {
        case .downloading, .loading: return true
        default: return false
        }
    }
}

actor TranscriptionManager {
    static let shared = TranscriptionManager()

    private var whisperKit: WhisperKit?
    private(set) var loadingState: TranscriptionLoadingState = .idle

    // Performance metrics
    private var totalTranscriptions: Int = 0
    private var totalTranscriptionTime: TimeInterval = 0
    private var totalAudioDuration: TimeInterval = 0

    private init() {}

    /// Get current loading state (for UI observation)
    func getLoadingState() -> TranscriptionLoadingState {
        return loadingState
    }

    /// Load WhisperKit model (downloads on first use) with retry
    func loadModel(retryCount: Int = 0) async throws {
        guard whisperKit == nil else { return }
        guard !loadingState.isLoading else {
            // Wait for existing load to complete
            while loadingState.isLoading {
                try await Task.sleep(nanoseconds: 100_000_000) // 100ms
            }
            return
        }

        let modelLoadStart = Date()
        loadingState = .downloading

        // Use tiny model - fastest and most compatible
        let modelName = "openai_whisper-tiny.en"

        print("[TranscriptionManager] Starting model load (attempt \(retryCount + 1))...")
        print("[TranscriptionManager] Model: \(modelName)")

        do {
            loadingState = .loading

            // CPU-only mode works everywhere including simulator
            print("[TranscriptionManager] Using CPU-only mode for maximum compatibility")
            whisperKit = try await WhisperKit(
                model: modelName,
                computeOptions: .init(
                    audioEncoderCompute: .cpuOnly,
                    textDecoderCompute: .cpuOnly
                ),
                verbose: true,
                prewarm: false,
                useBackgroundDownloadSession: true
            )

            let loadTime = Date().timeIntervalSince(modelLoadStart)
            loadingState = .ready
            print("[TranscriptionManager] Model loaded successfully in \(String(format: "%.2f", loadTime))s")

        } catch {
            let loadTime = Date().timeIntervalSince(modelLoadStart)
            print("[TranscriptionManager] Model load FAILED after \(String(format: "%.2f", loadTime))s: \(error)")

            // Retry up to 2 times
            if retryCount < 2 {
                print("[TranscriptionManager] Retrying in 1 second...")
                loadingState = .idle
                whisperKit = nil
                try await Task.sleep(nanoseconds: 1_000_000_000) // 1 second
                try await loadModel(retryCount: retryCount + 1)
            } else {
                loadingState = .error(error.localizedDescription)
                throw error
            }
        }
    }

    /// Force reload the model (for manual refresh)
    func reloadModel() async throws {
        whisperKit = nil
        loadingState = .idle
        try await loadModel()
    }

    /// Transcribe audio from WAV data
    func transcribe(audioData: Data) async throws -> String {
        let overallStart = Date()

        // Load model if needed
        if whisperKit == nil {
            print("[TranscriptionManager] Model not loaded, loading now...")
            try await loadModel()
        }

        guard let whisperKit = whisperKit else {
            throw TranscriptionError.modelNotLoaded
        }

        // Write to temp file (WhisperKit needs file URL)
        let fileWriteStart = Date()
        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("wav")

        try audioData.write(to: tempURL)
        let fileWriteTime = Date().timeIntervalSince(fileWriteStart)

        defer {
            try? FileManager.default.removeItem(at: tempURL)
        }

        // Get audio duration for RTF calculation
        let audioDuration = getAudioDuration(from: tempURL)
        let audioSizeKB = Double(audioData.count) / 1024.0

        print("[TranscriptionManager] Transcribing...")
        print("[TranscriptionManager]   Audio size: \(String(format: "%.1f", audioSizeKB)) KB")
        print("[TranscriptionManager]   Audio duration: \(String(format: "%.2f", audioDuration))s")
        print("[TranscriptionManager]   File write time: \(String(format: "%.3f", fileWriteTime))s")

        let transcriptionStart = Date()

        // Transcribe
        let results = try await whisperKit.transcribe(audioPath: tempURL.path)

        let transcriptionTime = Date().timeIntervalSince(transcriptionStart)
        let overallTime = Date().timeIntervalSince(overallStart)
        let transcript = results.map { $0.text }.joined(separator: " ").trimmingCharacters(in: .whitespaces)

        // Calculate Real-Time Factor (RTF): <1 means faster than real-time
        let rtf = audioDuration > 0 ? transcriptionTime / audioDuration : 0

        // Update cumulative metrics
        totalTranscriptions += 1
        totalTranscriptionTime += transcriptionTime
        totalAudioDuration += audioDuration

        // Performance logging
        print("[TranscriptionManager] Transcription complete!")
        print("[TranscriptionManager]   Transcription time: \(String(format: "%.2f", transcriptionTime))s")
        print("[TranscriptionManager]   Real-Time Factor: \(String(format: "%.2f", rtf))x (< 1.0 = faster than real-time)")
        print("[TranscriptionManager]   Total time (incl. file I/O): \(String(format: "%.2f", overallTime))s")
        print("[TranscriptionManager]   Result: \"\(transcript.prefix(80))...\"")
        print("[TranscriptionManager]   Session stats: \(totalTranscriptions) transcriptions, avg RTF: \(String(format: "%.2f", totalAudioDuration > 0 ? totalTranscriptionTime / totalAudioDuration : 0))x")

        return transcript
    }

    /// Get audio duration from file URL
    private func getAudioDuration(from url: URL) -> TimeInterval {
        do {
            let audioFile = try AVAudioFile(forReading: url)
            let duration = Double(audioFile.length) / audioFile.processingFormat.sampleRate
            return duration
        } catch {
            print("[TranscriptionManager] Could not get audio duration: \(error)")
            return 0
        }
    }

    /// Get performance statistics
    func getPerformanceStats() -> (count: Int, avgRTF: Double, totalAudio: TimeInterval) {
        let avgRTF = totalAudioDuration > 0 ? totalTranscriptionTime / totalAudioDuration : 0
        return (totalTranscriptions, avgRTF, totalAudioDuration)
    }
}

#else

// Fallback when WhisperKit not installed
actor TranscriptionManager {
    static let shared = TranscriptionManager()

    private init() {}

    func transcribe(audioData: Data) async throws -> String {
        print("⚠️ WhisperKit not installed - add via Swift Package Manager")
        print("   File > Add Package Dependencies")
        print("   URL: https://github.com/argmaxinc/WhisperKit")
        throw TranscriptionError.modelNotLoaded
    }
}

#endif

// MARK: - Errors

enum TranscriptionError: Error, LocalizedError {
    case modelNotFound(String)
    case modelNotLoaded
    case formatError
    case transcriptionFailed(String)

    var errorDescription: String? {
        switch self {
        case .modelNotFound(let path):
            return "Model not found at: \(path)"
        case .modelNotLoaded:
            return "Transcription model not loaded. Add WhisperKit package."
        case .formatError:
            return "Audio format error"
        case .transcriptionFailed(let msg):
            return "Transcription failed: \(msg)"
        }
    }
}
