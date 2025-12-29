import AVFoundation
import SwiftUI

// MARK: - Audio Player

final class AudioPlayer: NSObject, ObservableObject {
    @Published var isPlaying = false
    @Published var currentTime: TimeInterval = 0
    @Published var duration: TimeInterval = 0

    private var audioPlayer: AVAudioPlayer?
    private var progressTimer: Timer?

    override init() {
        super.init()
    }

    // MARK: - Playback Control

    func play(data: Data) {
        stop() // Stop any existing playback

        do {
            // Configure audio session for playback
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playback, mode: .default)
            try session.setActive(true)

            audioPlayer = try AVAudioPlayer(data: data)
            audioPlayer?.delegate = self
            audioPlayer?.prepareToPlay()

            duration = audioPlayer?.duration ?? 0
            currentTime = 0

            audioPlayer?.play()
            isPlaying = true

            startProgressTimer()

            print("[AudioPlayer] Playing audio: \(data.count) bytes, duration: \(duration)s")
        } catch {
            print("[AudioPlayer] Error playing audio: \(error)")
            isPlaying = false
        }
    }

    func pause() {
        audioPlayer?.pause()
        isPlaying = false
        stopProgressTimer()
        print("[AudioPlayer] Paused")
    }

    func resume() {
        audioPlayer?.play()
        isPlaying = true
        startProgressTimer()
        print("[AudioPlayer] Resumed")
    }

    func stop() {
        audioPlayer?.stop()
        audioPlayer = nil
        isPlaying = false
        currentTime = 0
        stopProgressTimer()
        print("[AudioPlayer] Stopped")
    }

    func seek(to time: TimeInterval) {
        guard let player = audioPlayer else { return }
        let clampedTime = max(0, min(time, player.duration))
        player.currentTime = clampedTime
        currentTime = clampedTime
        print("[AudioPlayer] Seeked to: \(clampedTime)s")
    }

    func togglePlayPause() {
        if isPlaying {
            pause()
        } else if audioPlayer != nil {
            resume()
        }
    }

    // MARK: - Progress Timer

    private func startProgressTimer() {
        stopProgressTimer()
        progressTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            guard let self = self, let player = self.audioPlayer else { return }
            self.currentTime = player.currentTime
        }
    }

    private func stopProgressTimer() {
        progressTimer?.invalidate()
        progressTimer = nil
    }
}

// MARK: - AVAudioPlayerDelegate

extension AudioPlayer: AVAudioPlayerDelegate {
    func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        DispatchQueue.main.async { [weak self] in
            self?.isPlaying = false
            self?.currentTime = self?.duration ?? 0
            self?.stopProgressTimer()
            print("[AudioPlayer] Finished playing, success: \(flag)")
        }
    }

    func audioPlayerDecodeErrorDidOccur(_ player: AVAudioPlayer, error: Error?) {
        DispatchQueue.main.async { [weak self] in
            self?.isPlaying = false
            self?.stopProgressTimer()
            print("[AudioPlayer] Decode error: \(error?.localizedDescription ?? "unknown")")
        }
    }
}
