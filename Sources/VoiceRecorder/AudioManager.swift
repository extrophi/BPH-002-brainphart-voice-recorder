//
//  AudioManager.swift
//  VoiceRecorder
//
//  Pure-Swift audio recording using AVAudioEngine.
//  Records 16kHz mono PCM buffers directly — Whisper-ready, no conversion needed.
//  Replaces the C++ AudioRecorder + FFmpeg pipeline.
//

@preconcurrency import AVFoundation
import Foundation

/// Thread-safe buffer that accumulates PCM data from the audio render thread
/// and delivers 35-second chunks back to the main thread.
private final class AudioBuffer: @unchecked Sendable {
    private let lock = NSLock()
    private var buffer = Data()
    private var _chunkIndex = 0
    private var _currentLevel: Float = 0

    let maxChunkBytes: Int
    var onChunkReady: ((Data, Int) -> Void)?

    init(maxChunkBytes: Int) {
        self.maxChunkBytes = maxChunkBytes
    }

    var currentLevel: Float {
        lock.lock()
        let level = _currentLevel
        lock.unlock()
        return level
    }

    var chunkIndex: Int {
        lock.lock()
        let idx = _chunkIndex
        lock.unlock()
        return idx
    }

    func reset() {
        lock.lock()
        buffer = Data()
        _chunkIndex = 0
        _currentLevel = 0
        lock.unlock()
    }

    func setLevel(_ level: Float) {
        lock.lock()
        _currentLevel = level
        lock.unlock()
    }

    /// Append PCM data and check for chunk boundary. Called from audio thread.
    func append(_ data: Data) {
        lock.lock()
        buffer.append(data)
        let currentSize = buffer.count
        lock.unlock()

        if currentSize >= maxChunkBytes {
            lock.lock()
            let chunkData = Data(buffer.prefix(maxChunkBytes))
            buffer = Data(buffer.dropFirst(maxChunkBytes))
            let idx = _chunkIndex
            _chunkIndex += 1
            lock.unlock()

            DispatchQueue.main.async { [weak self] in
                self?.onChunkReady?(chunkData, idx)
            }
        }
    }

    /// Flush remaining buffer as final chunk. Called from main thread.
    func flush() -> (Data, Int)? {
        lock.lock()
        let remaining = buffer
        buffer = Data()
        let idx = _chunkIndex
        _chunkIndex += 1
        lock.unlock()

        guard !remaining.isEmpty else { return nil }
        return (remaining, idx)
    }
}

@MainActor
final class AudioManager {

    // MARK: - Public State

    /// Whether recording is currently in progress.
    private(set) var isRecording = false

    /// Current audio metering level (0.0 - 1.0). Updated from tap callback.
    var currentLevel: Float {
        audioBuffer.currentLevel
    }

    // MARK: - Callbacks

    /// Called on main queue when a 35-second PCM chunk is ready.
    /// Provides raw 16kHz mono Float32 PCM data as bytes, and the chunk index.
    var onChunkComplete: ((Data, Int) -> Void)? {
        didSet { audioBuffer.onChunkReady = onChunkComplete }
    }

    // MARK: - Private

    private let engine = AVAudioEngine()

    /// Thread-safe accumulation buffer for PCM data.
    private let audioBuffer = AudioBuffer(
        maxChunkBytes: Config.burstLengthSeconds * Config.transcriptionSampleRate * MemoryLayout<Float>.size
    )

    /// The 16kHz mono format we record into (non-interleaved for AVAudioPCMBuffer compat).
    private nonisolated let recordingFormat: AVAudioFormat = {
        AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: Double(Config.transcriptionSampleRate),
            channels: 1,
            interleaved: false
        )!
    }()

    // MARK: - Recording Lifecycle

    /// Start recording from the default microphone.
    /// Audio is captured at 16kHz mono PCM via AVAudioEngine's installTap.
    /// Returns `true` if recording started successfully, `false` on failure.
    @discardableResult
    func startRecording() -> Bool {
        guard !isRecording else { return true }

        audioBuffer.reset()

        let inputNode = engine.inputNode
        let nativeFormat = inputNode.outputFormat(forBus: 0)

        // Validate mic format — 0 channels means no audio input device.
        guard nativeFormat.channelCount > 0 else {
            log.error("AudioManager: no audio input device (0 channels)")
            return false
        }

        log.info("AudioManager: mic native format: \(nativeFormat.sampleRate)Hz, \(nativeFormat.channelCount)ch")
        log.info("AudioManager: target format: \(self.recordingFormat.sampleRate)Hz, \(self.recordingFormat.channelCount)ch")

        // Create converter from mic format to 16kHz mono.
        guard let converter = AVAudioConverter(from: nativeFormat, to: recordingFormat) else {
            log.error("AudioManager: failed to create AVAudioConverter")
            return false
        }

        let audioBuffer = self.audioBuffer
        let recFormat = self.recordingFormat

        inputNode.installTap(onBus: 0, bufferSize: 4096, format: nativeFormat) { buffer, _ in
            AudioManager.processTapBuffer(buffer, converter: converter, recordingFormat: recFormat, audioBuffer: audioBuffer)
        }

        do {
            try engine.start()
            isRecording = true
            log.info("AudioManager: recording started (16kHz mono PCM)")
            return true
        } catch {
            log.error("AudioManager: failed to start engine: \(error)")
            inputNode.removeTap(onBus: 0)
            return false
        }
    }

    /// Stop recording and flush the final partial chunk.
    /// Returns the final flush data and chunk index so the caller can store it
    /// synchronously before starting transcription. Returns nil if no data remained.
    func stopRecording() -> (Data, Int)? {
        guard isRecording else { return nil }

        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        isRecording = false

        let finalChunk = audioBuffer.flush()
        let totalChunks = audioBuffer.chunkIndex

        if let (data, idx) = finalChunk {
            log.info("AudioManager: recording stopped, final chunk \(idx) = \(data.count) bytes, \(totalChunks) chunk(s) total")
        } else {
            log.warning("AudioManager: recording stopped, no data in final flush, \(totalChunks) chunk(s) total")
        }

        return finalChunk
    }

    /// Current metering level. Thread-safe.
    func getMeteringLevel() -> Float {
        audioBuffer.currentLevel
    }

    // MARK: - Tap Processing (background audio thread)

    /// Called on the audio render thread. Converts to 16kHz mono, computes RMS,
    /// accumulates into chunk buffer, and fires chunk callback at 35s boundaries.
    private static nonisolated func processTapBuffer(
        _ buffer: AVAudioPCMBuffer,
        converter: AVAudioConverter,
        recordingFormat: AVAudioFormat,
        audioBuffer: AudioBuffer
    ) {
        guard buffer.frameLength > 0 else { return }

        // Calculate output capacity based on sample rate ratio.
        let ratio = recordingFormat.sampleRate / buffer.format.sampleRate
        let outputFrameCapacity = AVAudioFrameCount(Double(buffer.frameLength) * ratio) + 16
        guard let outputBuffer = AVAudioPCMBuffer(pcmFormat: recordingFormat, frameCapacity: outputFrameCapacity) else { return }

        // Convert: the input block provides our buffer exactly once.
        var error: NSError?
        var consumed = false
        let status = converter.convert(to: outputBuffer, error: &error) { _, outStatus in
            if consumed {
                outStatus.pointee = .noDataNow
                return nil
            }
            consumed = true
            outStatus.pointee = .haveData
            return buffer
        }

        // Accept any status that produced output frames.
        // .haveData = output filled, .endOfStream = finished — just check we got frames.
        guard error == nil, status != .error, outputBuffer.frameLength > 0 else { return }

        guard let channelData = outputBuffer.floatChannelData else { return }
        let frameCount = Int(outputBuffer.frameLength)

        // Compute RMS for metering.
        let samples = channelData[0]
        var sum: Float = 0
        for i in 0..<frameCount {
            sum += samples[i] * samples[i]
        }
        let rms = sqrtf(sum / Float(frameCount))
        audioBuffer.setLevel(rms)

        // Copy PCM data and accumulate.
        let byteCount = frameCount * MemoryLayout<Float>.size
        let pcmData = Data(bytes: samples, count: byteCount)
        audioBuffer.append(pcmData)
    }

    // MARK: - PCM Utilities

    /// Create a WAV file header for 16kHz mono Float32 PCM data.
    /// Used for playback — wraps raw PCM bytes so AVAudioPlayer can play them.
    static func wavHeader(forPCMDataLength dataLength: Int) -> Data {
        let sampleRate: UInt32 = UInt32(Config.transcriptionSampleRate)
        let channels: UInt16 = 1
        let bitsPerSample: UInt16 = 32  // Float32
        let bytesPerSample = bitsPerSample / 8
        let byteRate = sampleRate * UInt32(channels) * UInt32(bytesPerSample)
        let blockAlign = channels * bytesPerSample

        var header = Data(capacity: 44)

        // RIFF header
        header.append(contentsOf: "RIFF".utf8)
        var chunkSize = UInt32(36 + dataLength)
        header.append(Data(bytes: &chunkSize, count: 4))
        header.append(contentsOf: "WAVE".utf8)

        // fmt subchunk
        header.append(contentsOf: "fmt ".utf8)
        var subchunk1Size: UInt32 = 16
        header.append(Data(bytes: &subchunk1Size, count: 4))
        var audioFormat: UInt16 = 3  // IEEE float
        header.append(Data(bytes: &audioFormat, count: 2))
        var numChannels = channels
        header.append(Data(bytes: &numChannels, count: 2))
        var sr = sampleRate
        header.append(Data(bytes: &sr, count: 4))
        var br = byteRate
        header.append(Data(bytes: &br, count: 4))
        var ba = blockAlign
        header.append(Data(bytes: &ba, count: 2))
        var bps = bitsPerSample
        header.append(Data(bytes: &bps, count: 2))

        // data subchunk
        header.append(contentsOf: "data".utf8)
        var subchunk2Size = UInt32(dataLength)
        header.append(Data(bytes: &subchunk2Size, count: 4))

        return header
    }

    /// Wrap raw PCM data with a WAV header for playback.
    static func pcmToWAV(_ pcmData: Data) -> Data {
        var wav = wavHeader(forPCMDataLength: pcmData.count)
        wav.append(pcmData)
        return wav
    }
}
