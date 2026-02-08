#pragma once

#include <cstdint>
#include <functional>
#include <string>
#include <vector>

namespace vr {

// ---------------------------------------------------------------------------
// Enums
// ---------------------------------------------------------------------------

enum class RecordingStatus {
    recording,
    transcribing,
    complete,
    failed
};

/// Convert status enum to the string stored in SQLite.
inline const char* status_to_string(RecordingStatus s) {
    switch (s) {
        case RecordingStatus::recording:    return "recording";
        case RecordingStatus::transcribing: return "transcribing";
        case RecordingStatus::complete:     return "complete";
        case RecordingStatus::failed:       return "failed";
    }
    return "unknown";
}

/// Parse status string from SQLite back to enum.
inline RecordingStatus status_from_string(const std::string& s) {
    if (s == "recording")    return RecordingStatus::recording;
    if (s == "transcribing") return RecordingStatus::transcribing;
    if (s == "complete")     return RecordingStatus::complete;
    if (s == "failed")       return RecordingStatus::failed;
    return RecordingStatus::failed;
}

// ---------------------------------------------------------------------------
// Structs
// ---------------------------------------------------------------------------

/// Represents one recording session (brain-dump).
struct RecordingSession {
    std::string     id;             // UUID as string
    int64_t         created_at;     // Unix timestamp (seconds)
    int64_t         completed_at;   // 0 if not yet completed
    RecordingStatus status;
    int64_t         duration_ms;    // Total duration across all chunks
    std::string     transcript;     // Final concatenated transcript
};

/// A single 35-second audio burst within a session.
struct AudioChunk {
    std::string             session_id;
    int32_t                 chunk_index;
    std::vector<uint8_t>    audio_data;     // Raw M4A file bytes
    int64_t                 duration_ms;
};

// ---------------------------------------------------------------------------
// Callback types
// ---------------------------------------------------------------------------

/// Fired during whisper transcription with progress 0.0 – 1.0.
using ProgressCallback = std::function<void(float)>;

/// Fired during recording with current audio level 0.0 – 1.0.
using MeteringCallback = std::function<void(float)>;

/// Fired when a 35-second burst chunk is finalized.
using BurstCallback = std::function<void(const AudioChunk&)>;

} // namespace vr
