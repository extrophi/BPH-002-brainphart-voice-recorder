import SwiftUI
#if os(macOS)
import AppKit
#endif

// MARK: - Micro Mode View (Pill)

struct MicroModeView: View {
    @ObservedObject var audioRecorder: AudioRecorder
    let onStartStop: () -> Void
    let onCancel: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            // Waveform
            WaveformIndicator(level: audioRecorder.audioLevel, isRecording: audioRecorder.isRecording)
                .frame(width: 120, height: 24)

            // Record button
            Button(action: onStartStop) {
                Circle()
                    .fill(audioRecorder.isRecording ? Color.red : Color.accentColor)
                    .frame(width: 24, height: 24)
                    .overlay(
                        audioRecorder.isRecording
                            ? AnyView(Rectangle().fill(.white).frame(width: 8, height: 8))
                            : AnyView(Circle().fill(.white).frame(width: 8, height: 8))
                    )
            }
            .buttonStyle(.plain)

            // Cancel button (only when recording)
            if audioRecorder.isRecording {
                Button(action: onCancel) {
                    Image(systemName: "xmark")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
                .keyboardShortcut(.escape, modifiers: [])
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        #if os(macOS)
        .background(Color(NSColor.windowBackgroundColor))
        #else
        .background(Color(.systemBackground))
        #endif
        .cornerRadius(24)
        .shadow(color: .black.opacity(0.15), radius: 8, x: 0, y: 2)
    }
}

// MARK: - Medium Mode View (Floating Panel)

struct MediumModeView: View {
    @ObservedObject var audioRecorder: AudioRecorder
    let onStartStop: () -> Void
    let onCancel: () -> Void

    var body: some View {
        VStack(spacing: 12) {
            // Header with timer
            HStack {
                // Logo
                Image(systemName: "waveform.circle.fill")
                    .font(.system(size: 20))
                    .foregroundColor(.accentColor)

                Text("BrainPhart")
                    .font(.system(size: 14, weight: .semibold))

                Spacer()

                // Timer
                if audioRecorder.isRecording {
                    Text(formatDuration(audioRecorder.recordingDuration))
                        .font(.system(size: 14, design: .monospaced))
                        .foregroundColor(.red)
                }

                // Mode toggle
                Button(action: {
                    AppState.shared.windowMode = .full
                }) {
                    Image(systemName: "arrow.up.left.and.arrow.down.right")
                        .font(.system(size: 12))
                }
                .buttonStyle(.plain)
                .help("Expand to full mode")
            }
            .padding(.horizontal)

            // Waveform
            WaveformIndicator(level: audioRecorder.audioLevel, isRecording: audioRecorder.isRecording)
                .frame(height: 32)
                .padding(.horizontal)

            // Controls
            HStack(spacing: 16) {
                // Cancel button
                Button(action: onCancel) {
                    HStack(spacing: 4) {
                        Image(systemName: "xmark")
                        Text("Cancel")
                    }
                    .font(.system(size: 12))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                }
                .buttonStyle(.plain)
                .background(Color.primary.opacity(0.06))
                .cornerRadius(6)
                .opacity(audioRecorder.isRecording ? 1 : 0.3)
                .disabled(!audioRecorder.isRecording)
                .keyboardShortcut(.escape, modifiers: [])

                Spacer()

                // Record/Stop button
                Button(action: onStartStop) {
                    HStack(spacing: 6) {
                        Circle()
                            .fill(audioRecorder.isRecording ? Color.red : Color.accentColor)
                            .frame(width: 10, height: 10)
                        Text(audioRecorder.isRecording ? "Stop" : "Record")
                            .font(.system(size: 12, weight: .medium))
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 6)
                    .background(audioRecorder.isRecording ? Color.red.opacity(0.15) : Color.accentColor.opacity(0.15))
                    .cornerRadius(6)
                }
                .buttonStyle(.plain)
                .keyboardShortcut("r", modifiers: [.control, .shift])
            }
            .padding(.horizontal)

            // Hotkey hint
            Text("Ctrl + Shift + Space")
                .font(.system(size: 10))
                .foregroundColor(.secondary)
        }
        .padding(.vertical, 12)
        #if os(macOS)
        .background(Color(NSColor.windowBackgroundColor))
        #else
        .background(Color(.systemBackground))
        #endif
        .cornerRadius(12)
        .shadow(color: .black.opacity(0.15), radius: 12, x: 0, y: 4)
        .frame(width: 300)
    }

    private func formatDuration(_ duration: TimeInterval) -> String {
        let mins = Int(duration) / 60
        let secs = Int(duration) % 60
        return String(format: "%02d:%02d", mins, secs)
    }
}

// MARK: - Full Mode View (Main Window)

struct FullModeView: View {
    @ObservedObject var audioRecorder: AudioRecorder
    @Binding var recordings: [RecordingItem]
    @Binding var selectedRecording: RecordingItem?
    @Binding var editedTranscript: String

    let onStartStop: () -> Void
    let onCancel: () -> Void
    let onSelect: (RecordingItem) -> Void
    let onSave: () -> Void
    let onDelete: (RecordingItem) -> Void
    let onRefresh: () -> Void

    var body: some View {
        HSplitView {
            // Left: History sidebar
            HistoryView(
                recordings: recordings,
                selectedId: selectedRecording?.id,
                onSelect: onSelect,
                onDelete: onDelete,
                onRefresh: onRefresh
            )
            .frame(minWidth: 220, idealWidth: 260, maxWidth: 320)

            // Right: Content area
            VStack(spacing: 0) {
                // Recording bar at top
                RecordingBar(
                    audioRecorder: audioRecorder,
                    onStartStop: onStartStop,
                    onCancel: onCancel
                )

                Divider()

                // Transcript view
                if let recording = selectedRecording {
                    TranscriptView(
                        recording: recording,
                        transcript: $editedTranscript,
                        onSave: onSave
                    )
                } else {
                    EmptyTranscriptView()
                }

                Divider()

                // Playback controls at bottom
                PlaybackView(sessionId: selectedRecording?.id)
            }
        }
    }
}

// MARK: - Recording Bar

struct RecordingBar: View {
    @ObservedObject var audioRecorder: AudioRecorder
    let onStartStop: () -> Void
    let onCancel: () -> Void

    var body: some View {
        HStack(spacing: 16) {
            // Record/Stop button
            Button(action: onStartStop) {
                HStack(spacing: 8) {
                    Circle()
                        .fill(audioRecorder.isRecording ? Color.red : Color.accentColor)
                        .frame(width: 12, height: 12)
                        .overlay(
                            audioRecorder.isRecording
                                ? AnyView(Rectangle().fill(.white).frame(width: 4, height: 4))
                                : AnyView(EmptyView())
                        )

                    Text(audioRecorder.isRecording ? "Stop Recording" : "Start Recording")
                        .font(.system(size: 13, weight: .medium))
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(audioRecorder.isRecording ? Color.red.opacity(0.15) : Color.accentColor.opacity(0.15))
                .cornerRadius(8)
            }
            .buttonStyle(.plain)
            .keyboardShortcut("r", modifiers: [.control, .shift])

            // Cancel button
            if audioRecorder.isRecording {
                Button(action: onCancel) {
                    HStack(spacing: 4) {
                        Image(systemName: "xmark")
                        Text("Cancel")
                    }
                    .font(.system(size: 12))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(Color.primary.opacity(0.06))
                    .cornerRadius(6)
                }
                .buttonStyle(.plain)
                .keyboardShortcut(.escape, modifiers: [])
            }

            // Waveform
            if audioRecorder.isRecording {
                WaveformIndicator(level: audioRecorder.audioLevel, isRecording: true)
                    .frame(maxWidth: .infinity, maxHeight: 24)
            } else {
                Spacer()
            }

            // Timer
            if audioRecorder.isRecording {
                Text(formatDuration(audioRecorder.recordingDuration))
                    .font(.system(size: 14, design: .monospaced))
                    .foregroundColor(.red)
            }

            // Mode toggle
            Button(action: {
                AppState.shared.windowMode = .medium
            }) {
                Image(systemName: "arrow.down.right.and.arrow.up.left")
                    .font(.system(size: 12))
            }
            .buttonStyle(.plain)
            .help("Collapse to floating mode")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        #if os(macOS)
        .background(Color(NSColor.controlBackgroundColor))
        #endif
    }

    private func formatDuration(_ duration: TimeInterval) -> String {
        let mins = Int(duration) / 60
        let secs = Int(duration) % 60
        return String(format: "%02d:%02d", mins, secs)
    }
}

// MARK: - Waveform Indicator

struct WaveformIndicator: View {
    let level: Float
    let isRecording: Bool

    private let barCount = 20

    var body: some View {
        GeometryReader { geo in
            HStack(alignment: .center, spacing: 2) {
                ForEach(0..<barCount, id: \.self) { index in
                    RoundedRectangle(cornerRadius: 1)
                        .fill(barColor(for: index))
                        .frame(
                            width: max(2, (geo.size.width / CGFloat(barCount)) - 2),
                            height: barHeight(for: index, maxHeight: geo.size.height)
                        )
                        .animation(.easeOut(duration: 0.1), value: level)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
        }
    }

    private func barColor(for index: Int) -> Color {
        if !isRecording {
            return Color.primary.opacity(0.2)
        }
        return Color.accentColor
    }

    private func barHeight(for index: Int, maxHeight: CGFloat) -> CGFloat {
        if !isRecording {
            // Static pattern when not recording
            let seed = sin(Double(index) * 0.5) * 0.3 + 0.3
            return max(4, CGFloat(seed) * maxHeight * 0.5)
        }

        // Dynamic based on audio level with some variation
        let base = CGFloat(level) * maxHeight
        let variation = sin(Double(index) * 0.8) * 0.3 + 0.7
        return max(4, base * CGFloat(variation))
    }
}

// MARK: - iOS Micro Recorder View (for menu bar style)

#if os(iOS)
struct MicroRecorderView: View {
    @EnvironmentObject var appState: AppState

    var body: some View {
        Text("Micro Mode iOS")
    }
}

struct MediumRecorderView: View {
    @EnvironmentObject var appState: AppState

    var body: some View {
        Text("Medium Mode iOS")
    }
}
#endif

#if os(macOS)
struct MicroRecorderView: View {
    @EnvironmentObject var appState: AppState

    var body: some View {
        MicroModeView(
            audioRecorder: AudioRecorder(),
            onStartStop: {},
            onCancel: {}
        )
    }
}

struct MediumRecorderView: View {
    @EnvironmentObject var appState: AppState

    var body: some View {
        MediumModeView(
            audioRecorder: AudioRecorder(),
            onStartStop: {},
            onCancel: {}
        )
    }
}
#endif
