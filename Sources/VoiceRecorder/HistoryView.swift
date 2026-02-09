//
//  HistoryView.swift
//  VoiceRecorder
//
//  Recording history browser.
//
//  Displays all persisted sessions in a scrollable list, newest first.
//  Each row shows timestamp, duration, status, and a one-line transcript
//  preview.  Expanding a row reveals the full transcript along with
//  playback, copy, retry, and delete controls.
//

import SwiftUI
import AppKit
import AVFoundation
import VoiceRecorderBridge

// MARK: - HistoryView

struct HistoryView: View {
    @Environment(AppState.self) private var appState

    /// Binding to the parent's selected session id for the detail pane.
    @Binding var selectedSessionId: String?

    /// Search query to filter sessions by transcript content.
    @State private var searchText = ""

    /// The session whose detail is currently expanded (nil = all collapsed).
    @State private var expandedSessionId: String?

    var body: some View {
        VStack(spacing: 0) {
            // Search bar.
            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                TextField("Search transcripts...", text: $searchText)
                    .textFieldStyle(.plain)
                if !searchText.isEmpty {
                    Button {
                        searchText = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(10)
            .background(.bar)

            Divider()

            // Session list.
            if filteredSessions.isEmpty {
                emptyStateView
            } else {
                ScrollView {
                    LazyVStack(spacing: 1) {
                        ForEach(filteredSessions, id: \.sessionId) { session in
                            SessionRow(
                                session: session,
                                isExpanded: expandedSessionId == session.sessionId,
                                onToggle: { toggleExpanded(session.sessionId) },
                                onCopy: { copyTranscript(session) },
                                onRetry: { appState.retryTranscription(sessionId: session.sessionId) },
                                onDelete: { appState.deleteSession(sessionId: session.sessionId) }
                            )
                        }
                    }
                    .padding(.vertical, 4)
                }
            }
        }
        .onAppear {
            appState.loadSessions()
        }
    }

    // MARK: - Filtered Sessions

    private var filteredSessions: [VRSession] {
        guard !searchText.isEmpty else { return appState.sessions }
        let query = searchText.lowercased()
        return appState.sessions.filter { session in
            session.transcript?.lowercased().contains(query) ?? false
        }
    }

    // MARK: - Helpers

    private func toggleExpanded(_ sessionId: String) {
        withAnimation(.easeInOut(duration: 0.2)) {
            if expandedSessionId == sessionId {
                expandedSessionId = nil
            } else {
                expandedSessionId = sessionId
            }
            // Also drive the detail pane selection.
            selectedSessionId = expandedSessionId
        }
    }

    private func copyTranscript(_ session: VRSession) {
        guard let text = session.transcript, !text.isEmpty else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }

    // MARK: - Empty State

    private var emptyStateView: some View {
        VStack(spacing: 12) {
            Spacer()
            Image(systemName: "waveform.slash")
                .font(.system(size: 40))
                .foregroundStyle(.tertiary)
            if searchText.isEmpty {
                Text("No recordings yet")
                    .font(.headline)
                    .foregroundStyle(.secondary)
                Text("Press Cmd+Shift+R to start recording")
                    .font(.subheadline)
                    .foregroundStyle(.tertiary)
            } else {
                Text("No matching recordings")
                    .font(.headline)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }
}

// MARK: - SessionRow

/// A single row in the history list showing one recording session.
private struct SessionRow: View {
    let session: VRSession
    let isExpanded: Bool
    let onToggle: () -> Void
    let onCopy: () -> Void
    let onRetry: () -> Void
    let onDelete: () -> Void

    @State private var audioPlayer: AVAudioPlayer?
    @State private var isPlaying = false

    @Environment(AppState.self) private var appState

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Summary row (always visible).
            summaryRow

            // Expanded detail.
            if isExpanded {
                detailView
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .background(isExpanded ? Color.accentColor.opacity(0.04) : Color.clear)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .padding(.horizontal, 8)
    }

    // MARK: - Summary Row

    private var summaryRow: some View {
        Button(action: onToggle) {
            HStack(spacing: 10) {
                statusIcon
                    .frame(width: 20)

                VStack(alignment: .leading, spacing: 2) {
                    Text(formattedDate)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(.primary)

                    if let preview = transcriptPreview {
                        Text(preview)
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.tail)
                    }
                }

                Spacer()

                Text(formattedDuration)
                    .font(.system(size: 12, weight: .regular, design: .monospaced))
                    .foregroundStyle(.tertiary)
                    .monospacedDigit()

                Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)
            }
            .padding(.vertical, 8)
            .padding(.horizontal, 10)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: - Detail View

    private var detailView: some View {
        VStack(alignment: .leading, spacing: 12) {
            Divider()
                .padding(.horizontal, 10)

            // Full transcript.
            if let transcript = session.transcript, !transcript.isEmpty {
                ScrollView {
                    Text(transcript)
                        .font(.system(size: 13))
                        .foregroundStyle(.primary)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(maxHeight: 200)
                .padding(.horizontal, 10)
            } else {
                Text("No transcript available")
                    .font(.system(size: 12, weight: .regular))
                    .foregroundStyle(.tertiary)
                    .italic()
                    .padding(.horizontal, 10)
            }

            // Action buttons.
            HStack(spacing: 12) {
                // Play / Stop.
                Button {
                    togglePlayback()
                } label: {
                    Label(isPlaying ? "Stop" : "Play",
                          systemImage: isPlaying ? "stop.fill" : "play.fill")
                }
                .buttonStyle(.bordered)

                // Copy.
                Button {
                    onCopy()
                } label: {
                    Label("Copy", systemImage: "doc.on.doc")
                }
                .buttonStyle(.bordered)
                .disabled(session.transcript?.isEmpty ?? true)

                // Retry transcription.
                Button {
                    onRetry()
                } label: {
                    Label("Retry", systemImage: "arrow.clockwise")
                }
                .buttonStyle(.bordered)

                Spacer()

                // Delete.
                Button(role: .destructive) {
                    stopPlayback()
                    onDelete()
                } label: {
                    Label("Delete", systemImage: "trash")
                }
                .buttonStyle(.bordered)
            }
            .padding(.horizontal, 10)
            .padding(.bottom, 10)
        }
    }

    // MARK: - Status Icon

    @ViewBuilder
    private var statusIcon: some View {
        switch session.status {
        case "recording":
            Image(systemName: "record.circle")
                .foregroundStyle(.red)
        case "transcribing":
            Image(systemName: "text.badge.star")
                .foregroundStyle(.orange)
        case "complete":
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(.green)
        case "failed":
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.red)
        default:
            Image(systemName: "questionmark.circle")
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Formatting

    private var formattedDate: String {
        let date = Date(timeIntervalSince1970: TimeInterval(session.createdAt))
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }

    private var formattedDuration: String {
        let totalSeconds = session.durationMs / 1000
        let minutes = totalSeconds / 60
        let seconds = totalSeconds % 60
        return String(format: "%d:%02d", minutes, seconds)
    }

    private var transcriptPreview: String? {
        guard let transcript = session.transcript, !transcript.isEmpty else { return nil }
        // Return the first line, trimmed.
        return transcript
            .components(separatedBy: .newlines)
            .first?
            .trimmingCharacters(in: .whitespaces)
    }

    // MARK: - Playback

    private func togglePlayback() {
        if isPlaying {
            stopPlayback()
        } else {
            startPlayback()
        }
    }

    private func startPlayback() {
        guard let pcmData = appState.storageBridge.getAudioForSession(session.sessionId) else {
            appState.setError("No audio data found for playback")
            return
        }

        if pcmData.count == 0 {
            appState.setError("Audio data is empty — cannot play")
            return
        }

        do {
            // Wrap raw PCM in a WAV header so AVAudioPlayer can play it.
            let wavData = AudioManager.pcmToWAV(pcmData as Data)
            let tempURL = FileManager.default.temporaryDirectory
                .appendingPathComponent("\(session.sessionId)_playback.wav")
            try wavData.write(to: tempURL, options: .atomic)

            let player = try AVAudioPlayer(contentsOf: tempURL)
            player.delegate = PlaybackDelegate.shared
            PlaybackDelegate.shared.onFinish = {
                DispatchQueue.main.async {
                    self.isPlaying = false
                    self.audioPlayer = nil
                    try? FileManager.default.removeItem(at: tempURL)
                }
            }
            player.prepareToPlay()
            let started = player.play()
            if !started {
                appState.setError("AVAudioPlayer.play() returned false")
                try? FileManager.default.removeItem(at: tempURL)
                return
            }
            audioPlayer = player
            isPlaying = true
        } catch {
            appState.setError("Playback error: \(error.localizedDescription)")
        }
    }

    private func stopPlayback() {
        audioPlayer?.stop()
        audioPlayer = nil
        isPlaying = false
    }
}

// MARK: - PlaybackDelegate

/// Simple AVAudioPlayerDelegate that calls a closure when playback finishes.
private final class PlaybackDelegate: NSObject, AVAudioPlayerDelegate, @unchecked Sendable {
    static let shared = PlaybackDelegate()
    var onFinish: (() -> Void)?

    func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        DispatchQueue.main.async { [weak self] in
            self?.onFinish?()
        }
    }
}
