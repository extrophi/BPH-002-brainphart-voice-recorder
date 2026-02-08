#pragma once

#include "AudioConverter.hpp"
#include "AudioRecorder.hpp"
#include "DatabaseManager.hpp"
#include "Types.hpp"
#include "WhisperEngine.hpp"

#include <functional>
#include <memory>
#include <mutex>
#include <string>
#include <thread>

namespace vr {

/// High-level orchestrator that coordinates the full recording lifecycle:
///
///   start_recording()  -->  [35s chunks]  -->  stop_recording()
///          |                     |                    |
///     create session       store chunks         transcribe
///                                                    |
///                                              update session
///
/// On initialization, performs crash recovery: any sessions stuck in
/// 'recording' status are recovered by transcribing their stored chunks.
class StorageManager {
public:
    /// Callback fired when transcription completes (or fails).
    using TranscriptionDoneCallback =
        std::function<void(const std::string& session_id,
                           const std::string& transcript,
                           bool success)>;

    /// Construct with explicit paths. Both are resolved by the caller.
    /// @param db_path   Full path to the SQLite database file.
    /// @param data_dir  Directory for temporary chunk files.
    StorageManager(const std::string& db_path, const std::string& data_dir);
    ~StorageManager();

    // Non-copyable.
    StorageManager(const StorageManager&) = delete;
    StorageManager& operator=(const StorageManager&) = delete;

    /// Initialize all subsystems.
    /// @param model_path  Path to the whisper ggml model file.
    /// @param data_dir    Base directory for temporary chunk files.
    ///                    If empty, uses ~/Library/Application Support/VoiceRecorder/chunks/
    /// @return true if database and whisper engine initialized.
    bool init(const std::string& model_path,
              const std::string& data_dir = "");

    // ---- Recording lifecycle ----

    /// Start a new recording session.  Returns the session UUID.
    /// Returns empty string on failure.
    std::string start_recording(MeteringCallback meter_cb = nullptr);

    /// Stop the current recording and begin transcription in background.
    /// @param done_cb  Called on a background thread when transcription finishes.
    void stop_recording(TranscriptionDoneCallback done_cb = nullptr);

    /// Whether a recording is currently in progress.
    bool is_recording() const;

    /// Current audio level (0.0 - 1.0) during recording.
    float get_metering() const;

    // ---- Transcription ----

    /// Transcribe a session's chunks.  Blocks until done.
    /// Returns the full transcript, or empty string on failure.
    std::string transcribe_session(const std::string& session_id,
                                   ProgressCallback progress = nullptr);

    // ---- Data access (delegates to DatabaseManager) ----

    std::vector<RecordingSession> get_sessions() const;
    std::optional<RecordingSession> get_session(const std::string& id) const;
    bool delete_session(const std::string& id);

    // ---- Crash recovery ----

    /// Recover orphaned sessions (status = 'recording').
    /// Called automatically during init().
    void recover_orphaned_sessions();

private:
    // ---- Subsystems ----
    DatabaseManager     db_;
    WhisperEngine       whisper_;
    AudioConverter      converter_;
    AudioRecorder       recorder_;

    // ---- State ----
    std::string         data_dir_;
    std::string         current_session_id_;
    mutable std::mutex  mu_;

    // Background transcription thread for stop_recording().
    std::thread         transcription_thread_;
};

} // namespace vr
