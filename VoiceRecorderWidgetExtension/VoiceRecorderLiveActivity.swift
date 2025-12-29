import ActivityKit
import WidgetKit
import SwiftUI

// NOTE: VoiceRecorderAttributes is defined in VoiceRecorderAttributes.swift (shared file)

// MARK: - Live Activity Widget

@available(iOS 16.1, *)
struct VoiceRecorderLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: VoiceRecorderAttributes.self) { context in
            // Lock Screen / Banner UI
            LockScreenView(context: context)
        } dynamicIsland: { context in
            DynamicIsland {
                // Expanded UI regions
                DynamicIslandExpandedRegion(.leading) {
                    RecordingIndicator(isRecording: context.state.isRecording)
                        .padding(.leading, 8)
                }

                DynamicIslandExpandedRegion(.trailing) {
                    TimerView(duration: context.state.duration)
                        .padding(.trailing, 8)
                }

                DynamicIslandExpandedRegion(.center) {
                    Text("Recording")
                        .font(.headline)
                        .foregroundColor(.white)
                }

                DynamicIslandExpandedRegion(.bottom) {
                    HStack {
                        Text("Tap to return to Voice Recorder")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .padding(.bottom, 4)
                }
            } compactLeading: {
                // Compact leading - small recording dot
                RecordingDot(isRecording: context.state.isRecording)
                    .frame(width: 12, height: 12)
            } compactTrailing: {
                // Compact trailing - timer
                Text(formatDuration(context.state.duration))
                    .font(.system(size: 14, weight: .medium, design: .monospaced))
                    .foregroundColor(.white)
                    .monospacedDigit()
            } minimal: {
                // Minimal - just the recording dot
                RecordingDot(isRecording: context.state.isRecording)
                    .frame(width: 12, height: 12)
            }
            .widgetURL(URL(string: "voicerecorder://open"))
            .keylineTint(.red)
        }
    }

    private func formatDuration(_ duration: TimeInterval) -> String {
        let mins = Int(duration) / 60
        let secs = Int(duration) % 60
        return String(format: "%02d:%02d", mins, secs)
    }
}

// MARK: - Lock Screen View

@available(iOS 16.1, *)
struct LockScreenView: View {
    let context: ActivityViewContext<VoiceRecorderAttributes>

    var body: some View {
        HStack(spacing: 16) {
            // Recording indicator
            RecordingIndicator(isRecording: context.state.isRecording)

            VStack(alignment: .leading, spacing: 4) {
                Text("Voice Recorder")
                    .font(.headline)
                    .foregroundColor(.white)

                Text(context.state.isRecording ? "Recording..." : "Paused")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }

            Spacer()

            // Timer
            TimerView(duration: context.state.duration)
        }
        .padding(16)
        .activityBackgroundTint(.black.opacity(0.8))
        .activitySystemActionForegroundColor(.white)
    }
}

// MARK: - Recording Indicator

@available(iOS 16.1, *)
struct RecordingIndicator: View {
    let isRecording: Bool

    var body: some View {
        ZStack {
            Circle()
                .fill(isRecording ? Color.red : Color.gray)
                .frame(width: 32, height: 32)

            if isRecording {
                Circle()
                    .stroke(Color.red.opacity(0.5), lineWidth: 2)
                    .frame(width: 40, height: 40)
                    .scaleEffect(1.2)
                    .opacity(0.6)
            }
        }
    }
}

// MARK: - Recording Dot (Compact)

@available(iOS 16.1, *)
struct RecordingDot: View {
    let isRecording: Bool

    var body: some View {
        Circle()
            .fill(isRecording ? Color.red : Color.gray)
    }
}

// MARK: - Timer View

@available(iOS 16.1, *)
struct TimerView: View {
    let duration: TimeInterval

    var body: some View {
        Text(formatDuration(duration))
            .font(.system(size: 24, weight: .medium, design: .monospaced))
            .foregroundColor(.white)
            .monospacedDigit()
    }

    private func formatDuration(_ duration: TimeInterval) -> String {
        let mins = Int(duration) / 60
        let secs = Int(duration) % 60
        return String(format: "%02d:%02d", mins, secs)
    }
}

// MARK: - Preview

@available(iOS 16.1, *)
#Preview("Live Activity", as: .content, using: VoiceRecorderAttributes(sessionId: "preview")) {
    VoiceRecorderLiveActivity()
} contentStates: {
    VoiceRecorderAttributes.ContentState(duration: 65, isRecording: true)
    VoiceRecorderAttributes.ContentState(duration: 120, isRecording: false)
}
