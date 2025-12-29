import ActivityKit
import Foundation

// MARK: - Activity Attributes (Shared between App and Widget Extension)

/// Defines the static and dynamic content for the Voice Recorder Live Activity
/// This file must be included in BOTH the main app target and widget extension target
public struct VoiceRecorderAttributes: ActivityAttributes {
    /// Dynamic content that changes during the activity
    public struct ContentState: Codable, Hashable {
        /// Current recording duration in seconds
        public var duration: TimeInterval
        /// Whether currently recording (vs paused)
        public var isRecording: Bool

        public init(duration: TimeInterval, isRecording: Bool) {
            self.duration = duration
            self.isRecording = isRecording
        }
    }

    /// Session identifier for this recording
    public var sessionId: String

    public init(sessionId: String) {
        self.sessionId = sessionId
    }
}
