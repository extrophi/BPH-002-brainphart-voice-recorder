import SwiftUI
import AVFoundation

// MARK: - Playback View

struct PlaybackView: View {
    let sessionId: String?
    @StateObject private var player = AudioPlayer()

    var body: some View {
        HStack(spacing: 16) {
            // Rewind 15s
            Button(action: { player.skip(seconds: -15) }) {
                Image(systemName: "gobackward.15")
                    .font(.system(size: 16))
            }
            .buttonStyle(.plain)
            .disabled(!player.isLoaded)

            // Play/Pause
            Button(action: { player.togglePlayPause() }) {
                Image(systemName: player.isPlaying ? "pause.fill" : "play.fill")
                    .font(.system(size: 20))
            }
            .buttonStyle(.plain)
            .disabled(!player.isLoaded)

            // Forward 15s
            Button(action: { player.skip(seconds: 15) }) {
                Image(systemName: "goforward.15")
                    .font(.system(size: 16))
            }
            .buttonStyle(.plain)
            .disabled(!player.isLoaded)

            // Scrubber with waveform
            ZStack {
                // Simple waveform background
                WaveformView(progress: player.progress)
                    .frame(height: 30)

                // Scrubber
                Slider(value: $player.progress, in: 0...1) { editing in
                    if !editing {
                        player.seek(to: player.progress)
                    }
                }
                .tint(.clear)
            }
            .frame(maxWidth: .infinity)

            // Time display
            Text(player.timeDisplay)
                .font(.system(size: 11, design: .monospaced))
                .foregroundColor(.secondary)
                .frame(width: 90)

            // Volume
            HStack(spacing: 4) {
                Image(systemName: "speaker.fill")
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
                Slider(value: $player.volume, in: 0...1)
                    .frame(width: 60)
                    .tint(.primary)
            }

            // Speed
            Menu {
                Button("0.5x") { player.setSpeed(0.5) }
                Button("1.0x") { player.setSpeed(1.0) }
                Button("1.5x") { player.setSpeed(1.5) }
                Button("2.0x") { player.setSpeed(2.0) }
            } label: {
                Text(player.speedLabel)
                    .font(.system(size: 11, weight: .medium))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.primary.opacity(0.08))
                    .cornerRadius(4)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 10)
        #if os(macOS)
        .background(Color(NSColor.controlBackgroundColor))
        #endif
        .onChange(of: sessionId) { newSessionId in
            if let id = newSessionId {
                player.load(sessionId: id)
            }
        }
        .onAppear {
            if let id = sessionId {
                player.load(sessionId: id)
            }
        }
    }
}

// MARK: - Waveform View

struct WaveformView: View {
    let progress: Double

    private let barCount = 50

    var body: some View {
        GeometryReader { geo in
            HStack(alignment: .center, spacing: 2) {
                ForEach(0..<barCount, id: \.self) { index in
                    let barProgress = Double(index) / Double(barCount)
                    let isPast = barProgress < progress

                    RoundedRectangle(cornerRadius: 1)
                        .fill(isPast ? Color.accentColor : Color.primary.opacity(0.2))
                        .frame(
                            width: max(1, (geo.size.width / CGFloat(barCount)) - 2),
                            height: randomHeight(for: index, maxHeight: geo.size.height)
                        )
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
        }
    }

    private func randomHeight(for index: Int, maxHeight: CGFloat) -> CGFloat {
        // Generate pseudo-random heights based on index
        let seed = sin(Double(index) * 0.5) * 0.5 + 0.5
        return max(4, CGFloat(seed) * maxHeight * 0.8)
    }
}

// MARK: - Audio Player

@MainActor
class AudioPlayer: ObservableObject {
    @Published var isPlaying = false
    @Published var isLoaded = false
    @Published var progress: Double = 0
    @Published var volume: Double = 1.0 {
        didSet { avPlayer?.volume = Float(volume) }
    }
    @Published var speed: Float = 1.0
    @Published var currentTime: TimeInterval = 0
    @Published var duration: TimeInterval = 0

    private var avPlayer: AVAudioPlayer?
    private var timer: Timer?
    private var audioChunks: [Data] = []
    private var currentChunkIndex = 0

    var timeDisplay: String {
        let current = formatTime(currentTime)
        let total = formatTime(duration)
        return "\(current) / \(total)"
    }

    var speedLabel: String {
        return String(format: "%.1fx", speed)
    }

    func load(sessionId: String) {
        stop()

        // Get audio chunks from database
        audioChunks = DatabaseManager.shared.getChunkAudio(sessionId: sessionId)

        guard !audioChunks.isEmpty else {
            print("No audio chunks found for session: \(sessionId)")
            isLoaded = false
            return
        }

        print("Loading \(audioChunks.count) chunk(s) for playback")

        // Calculate total duration
        duration = 0
        for data in audioChunks {
            if let player = try? AVAudioPlayer(data: data) {
                duration += player.duration
            }
        }

        // Load first chunk
        loadChunk(at: 0)
        isLoaded = true

        print("Playback ready: \(formatTime(duration)) total")
    }

    private func loadChunk(at index: Int) {
        guard index < audioChunks.count else { return }

        currentChunkIndex = index

        do {
            avPlayer = try AVAudioPlayer(data: audioChunks[index])
            avPlayer?.enableRate = true
            avPlayer?.rate = speed
            avPlayer?.volume = Float(volume)
            avPlayer?.prepareToPlay()
        } catch {
            print("Failed to load chunk \(index): \(error)")
        }
    }

    func togglePlayPause() {
        if isPlaying {
            pause()
        } else {
            play()
        }
    }

    func play() {
        guard isLoaded else { return }

        avPlayer?.play()
        isPlaying = true

        timer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.updateProgress()
            }
        }
    }

    func pause() {
        avPlayer?.pause()
        isPlaying = false
        timer?.invalidate()
    }

    func stop() {
        avPlayer?.stop()
        avPlayer = nil
        isPlaying = false
        timer?.invalidate()
        currentTime = 0
        progress = 0
        currentChunkIndex = 0
    }

    func skip(seconds: Double) {
        let newTime = currentTime + seconds
        let clampedTime = max(0, min(newTime, duration))
        seekToTime(clampedTime)
    }

    func seek(to progress: Double) {
        let targetTime = duration * progress
        seekToTime(targetTime)
    }

    private func seekToTime(_ time: TimeInterval) {
        // Find which chunk this time falls into
        var accumulatedTime: TimeInterval = 0

        for (index, data) in audioChunks.enumerated() {
            if let player = try? AVAudioPlayer(data: data) {
                let chunkDuration = player.duration

                if time < accumulatedTime + chunkDuration {
                    // Found the chunk
                    if index != currentChunkIndex {
                        loadChunk(at: index)
                    }
                    avPlayer?.currentTime = time - accumulatedTime
                    currentTime = time
                    progress = duration > 0 ? time / duration : 0

                    if isPlaying {
                        avPlayer?.play()
                    }
                    return
                }
                accumulatedTime += chunkDuration
            }
        }
    }

    private func updateProgress() {
        guard let player = avPlayer else { return }

        // Calculate time offset for current chunk
        var chunkOffset: TimeInterval = 0
        for i in 0..<currentChunkIndex {
            if let p = try? AVAudioPlayer(data: audioChunks[i]) {
                chunkOffset += p.duration
            }
        }

        currentTime = chunkOffset + player.currentTime
        progress = duration > 0 ? currentTime / duration : 0

        // Check if chunk finished
        if !player.isPlaying && isPlaying {
            // Move to next chunk
            if currentChunkIndex + 1 < audioChunks.count {
                loadChunk(at: currentChunkIndex + 1)
                avPlayer?.play()
            } else {
                // Finished all chunks
                stop()
                print("Playback complete")
            }
        }
    }

    func setSpeed(_ newSpeed: Float) {
        speed = newSpeed
        avPlayer?.rate = newSpeed
    }

    private func formatTime(_ time: TimeInterval) -> String {
        let mins = Int(time) / 60
        let secs = Int(time) % 60
        return String(format: "%02d:%02d", mins, secs)
    }
}
