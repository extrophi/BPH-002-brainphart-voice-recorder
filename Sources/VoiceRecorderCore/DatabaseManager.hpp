#pragma once

#include "Types.hpp"
#include <memory>
#include <mutex>
#include <optional>
#include <string>
#include <vector>

// Forward-declare sqlite3 so we don't leak its header into consumers.
struct sqlite3;

namespace vr {

/// Persistent storage for recording sessions and audio chunks.
///
/// Database location:
///   ~/Library/Application Support/VoiceRecorder/voicerecorder.db
///
/// Uses SQLite WAL mode for crash-safe writes.  All mutating operations
/// are wrapped in explicit transactions.
class DatabaseManager {
public:
    /// Construct with an explicit database file path.
    /// The path is resolved by the caller (typically the Swift/Obj-C layer
    /// using FileManager, which handles sandbox correctly).
    explicit DatabaseManager(const std::string& db_path);
    ~DatabaseManager();

    // Non-copyable.
    DatabaseManager(const DatabaseManager&) = delete;
    DatabaseManager& operator=(const DatabaseManager&) = delete;

    /// Open (or create) the database.  Returns false on failure.
    /// Automatically runs migrations / creates tables.
    bool open();

    /// Explicitly close the database.
    void close();

    /// Whether the database is open.
    bool is_open() const;

    // ---- Sessions ----

    /// Create a new recording session.  Returns the generated UUID.
    std::string create_session();

    /// Update the transcript for a session and mark it complete.
    bool update_transcript(const std::string& session_id,
                           const std::string& transcript,
                           int64_t duration_ms);

    /// Mark a session as failed.
    bool mark_failed(const std::string& session_id);

    /// Mark a session as transcribing.
    bool update_status(const std::string& session_id, RecordingStatus status);

    /// Update the duration_ms for a session.
    bool update_duration(const std::string& session_id, int64_t duration_ms);

    /// Retrieve a single session by ID.
    std::optional<RecordingSession> get_session(const std::string& session_id) const;

    /// Retrieve all sessions, most recent first.
    std::vector<RecordingSession> get_sessions() const;

    /// Delete a session and all its chunks.
    bool delete_session(const std::string& session_id);

    /// Find sessions still in 'recording' status (crash recovery).
    std::vector<RecordingSession> get_orphaned_sessions() const;

    // ---- Chunks ----

    /// Append an audio chunk to a session.
    bool add_chunk(const std::string& session_id,
                   int chunk_index,
                   const std::vector<uint8_t>& audio_data,
                   int64_t duration_ms);

    /// Retrieve all chunks for a session, ordered by chunk_index.
    std::vector<AudioChunk> get_chunks(const std::string& session_id) const;

private:
    /// Run the schema migration (CREATE TABLE IF NOT EXISTS ...).
    bool create_tables();

    /// Generate a UUID v4 string.
    static std::string generate_uuid();

    /// Current Unix timestamp in seconds.
    static int64_t now_unix();

    std::string     db_path_;
    sqlite3*        db_ = nullptr;
    mutable std::mutex mu_;
};

} // namespace vr
