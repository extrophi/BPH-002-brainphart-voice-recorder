import Foundation

// MARK: - Shared Storage for Keyboard Extension
// Uses App Groups to share data between main app and keyboard extension

final class SharedStorage {
    static let shared = SharedStorage()

    private let appGroupID = "group.com.brainphart.voicerecorder"
    private let transcriptKey = "latestTranscript"
    private let timestampKey = "transcriptTimestamp"

    private var userDefaults: UserDefaults? {
        UserDefaults(suiteName: appGroupID)
    }

    private init() {}

    // MARK: - Transcript Storage

    /// Save transcript for keyboard extension to access
    func saveTranscript(_ transcript: String) {
        guard let defaults = userDefaults else {
            print("[SharedStorage] Failed to access App Group")
            return
        }

        defaults.set(transcript, forKey: transcriptKey)
        defaults.set(Date().timeIntervalSince1970, forKey: timestampKey)
        defaults.synchronize()

        print("[SharedStorage] Saved transcript: \(transcript.prefix(50))...")
    }

    /// Get the latest transcript
    func getTranscript() -> String? {
        return userDefaults?.string(forKey: transcriptKey)
    }

    /// Get when the transcript was saved
    func getTranscriptTimestamp() -> Date? {
        guard let timestamp = userDefaults?.double(forKey: timestampKey), timestamp > 0 else {
            return nil
        }
        return Date(timeIntervalSince1970: timestamp)
    }

    /// Clear the stored transcript
    func clearTranscript() {
        userDefaults?.removeObject(forKey: transcriptKey)
        userDefaults?.removeObject(forKey: timestampKey)
        userDefaults?.synchronize()
    }

    /// Check if there's a recent transcript (within last hour)
    var hasRecentTranscript: Bool {
        guard let timestamp = getTranscriptTimestamp() else { return false }
        return Date().timeIntervalSince(timestamp) < 3600 // 1 hour
    }
}
