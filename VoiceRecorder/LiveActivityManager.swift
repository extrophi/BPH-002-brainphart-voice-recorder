import Foundation
import ActivityKit

// MARK: - Live Activity Manager

/// Manages Live Activity for voice recording sessions
/// Shows recording status in Dynamic Island when app is in background
@MainActor
final class LiveActivityManager: ObservableObject {
    static let shared = LiveActivityManager()

    @Published private(set) var isActivityActive = false

    private var currentActivity: Activity<VoiceRecorderAttributes>?
    private var updateTimer: Timer?

    private init() {}

    // MARK: - Public API

    /// Start a Live Activity for a new recording session
    /// - Parameters:
    ///   - sessionId: Unique identifier for the recording session
    func startActivity(sessionId: String) {
        guard ActivityAuthorizationInfo().areActivitiesEnabled else {
            print("[LiveActivity] Live Activities not enabled")
            return
        }

        // End any existing activity first
        endActivity()

        let attributes = VoiceRecorderAttributes(sessionId: sessionId)
        let initialState = VoiceRecorderAttributes.ContentState(
            duration: 0,
            isRecording: true
        )

        do {
            let activity = try Activity.request(
                attributes: attributes,
                content: .init(state: initialState, staleDate: nil),
                pushType: nil
            )
            currentActivity = activity
            isActivityActive = true
            print("[LiveActivity] Started activity: \(activity.id)")
        } catch {
            print("[LiveActivity] Failed to start: \(error)")
        }
    }

    /// Update the Live Activity with new duration
    /// - Parameters:
    ///   - duration: Current recording duration in seconds
    ///   - isRecording: Whether recording is active
    func updateActivity(duration: TimeInterval, isRecording: Bool) {
        guard let activity = currentActivity else { return }

        let updatedState = VoiceRecorderAttributes.ContentState(
            duration: duration,
            isRecording: isRecording
        )

        Task {
            await activity.update(
                ActivityContent(state: updatedState, staleDate: nil)
            )
        }
    }

    /// Pause the recording (updates UI to show paused state)
    /// - Parameter duration: Current duration when paused
    func pauseActivity(duration: TimeInterval) {
        updateActivity(duration: duration, isRecording: false)
    }

    /// Resume the recording
    /// - Parameter duration: Current duration when resumed
    func resumeActivity(duration: TimeInterval) {
        updateActivity(duration: duration, isRecording: true)
    }

    /// End the Live Activity
    /// - Parameter finalDuration: Final recording duration (optional)
    func endActivity(finalDuration: TimeInterval? = nil) {
        guard let activity = currentActivity else { return }

        let finalState = VoiceRecorderAttributes.ContentState(
            duration: finalDuration ?? 0,
            isRecording: false
        )

        Task {
            await activity.end(
                ActivityContent(state: finalState, staleDate: nil),
                dismissalPolicy: .immediate
            )
            print("[LiveActivity] Ended activity: \(activity.id)")
        }

        currentActivity = nil
        isActivityActive = false
    }

    /// End all active Live Activities for this app
    func endAllActivities() {
        Task {
            for activity in Activity<VoiceRecorderAttributes>.activities {
                await activity.end(
                    ActivityContent(
                        state: VoiceRecorderAttributes.ContentState(
                            duration: 0,
                            isRecording: false
                        ),
                        staleDate: nil
                    ),
                    dismissalPolicy: .immediate
                )
            }
        }
        currentActivity = nil
        isActivityActive = false
    }

    // MARK: - Convenience

    /// Check if Live Activities are available on this device
    var areActivitiesEnabled: Bool {
        ActivityAuthorizationInfo().areActivitiesEnabled
    }
}

// MARK: - AudioRecorder Extension

extension AudioRecorder {
    /// Start recording with Live Activity support
    func startRecordingWithLiveActivity(sessionId: String) async {
        await startRecording(sessionId: sessionId)

        await MainActor.run {
            LiveActivityManager.shared.startActivity(sessionId: sessionId)
        }
    }

    /// Stop recording and end Live Activity
    func stopRecordingWithLiveActivity() {
        let finalDuration = recordingDuration
        stopRecording()

        Task { @MainActor in
            LiveActivityManager.shared.endActivity(finalDuration: finalDuration)
        }
    }

    /// Update Live Activity with current duration
    /// Call this from your recording timer
    func updateLiveActivityDuration() {
        Task { @MainActor in
            LiveActivityManager.shared.updateActivity(
                duration: self.recordingDuration,
                isRecording: self.isRecording
            )
        }
    }
}
