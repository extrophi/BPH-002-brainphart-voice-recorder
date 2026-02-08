#include "StorageManager.hpp"

#include <filesystem>
#include <fstream>
#include <numeric>

namespace vr {

// ---------------------------------------------------------------------------
// Construction / destruction
// ---------------------------------------------------------------------------

StorageManager::StorageManager(const std::string& db_path,
                               const std::string& data_dir)
    : db_(db_path), data_dir_(data_dir) {
    std::filesystem::create_directories(data_dir_);
}

StorageManager::~StorageManager() {
    // Ensure recording is stopped cleanly.
    if (recorder_.is_recording()) {
        recorder_.stop_recording();
    }

    // Wait for any pending transcription thread.
    if (transcription_thread_.joinable()) {
        transcription_thread_.join();
    }
}

// ---------------------------------------------------------------------------
// init
// ---------------------------------------------------------------------------

bool StorageManager::init(const std::string& model_path,
                          const std::string& data_dir) {
    std::lock_guard<std::mutex> lock(mu_);

    // Data directory already set by constructor.
    std::filesystem::create_directories(data_dir_);

    // Open the database.
    if (!db_.open()) {
        return false;
    }

    // Load the whisper model.
    // This may fail if the model file doesn't exist yet — that's OK.
    // Transcription will just return empty strings until a model is loaded.
    whisper_.init(model_path);

    // Recover any sessions that were interrupted by a crash.
    recover_orphaned_sessions();

    return true;
}

// ---------------------------------------------------------------------------
// start_recording
// ---------------------------------------------------------------------------

std::string StorageManager::start_recording(MeteringCallback meter_cb) {
    std::lock_guard<std::mutex> lock(mu_);

    if (recorder_.is_recording()) {
        return "";   // already recording
    }

    // Create a new session in the database.
    std::string session_id = db_.create_session();
    if (session_id.empty()) {
        return "";
    }

    current_session_id_ = session_id;

    // Set up burst callback: when each 35-second chunk completes,
    // persist it to the database.
    BurstCallback burst_cb = [this, session_id](const AudioChunk& chunk) {
        db_.add_chunk(session_id,
                      chunk.chunk_index,
                      chunk.audio_data,
                      chunk.duration_ms);
    };

    // Create a per-session chunk directory.
    std::string session_dir = data_dir_ + "/" + session_id;
    std::filesystem::create_directories(session_dir);

    // Start the recorder.
    if (!recorder_.start_recording(session_dir, session_id,
                                   std::move(burst_cb),
                                   std::move(meter_cb))) {
        db_.mark_failed(session_id);
        current_session_id_.clear();
        return "";
    }

    return session_id;
}

// ---------------------------------------------------------------------------
// stop_recording
// ---------------------------------------------------------------------------

void StorageManager::stop_recording(TranscriptionDoneCallback done_cb) {
    std::string session_id;

    {
        std::lock_guard<std::mutex> lock(mu_);

        if (!recorder_.is_recording() || current_session_id_.empty()) {
            if (done_cb) done_cb("", "", false);
            return;
        }

        session_id = current_session_id_;
        current_session_id_.clear();
    }

    // Stop the recorder (this finalizes the last chunk and persists it
    // via the burst callback).
    recorder_.stop_recording();

    // Mark session as transcribing.
    db_.update_status(session_id, RecordingStatus::transcribing);

    // Wait for any previous transcription thread to finish.
    if (transcription_thread_.joinable()) {
        transcription_thread_.join();
    }

    // Launch transcription on a background thread.
    transcription_thread_ = std::thread(
        [this, session_id, done_cb = std::move(done_cb)]() {
            std::string transcript = transcribe_session(session_id);

            bool success = !transcript.empty();
            if (done_cb) {
                done_cb(session_id, transcript, success);
            }
        });
}

// ---------------------------------------------------------------------------
// is_recording / get_metering
// ---------------------------------------------------------------------------

bool StorageManager::is_recording() const {
    return recorder_.is_recording();
}

float StorageManager::get_metering() const {
    return recorder_.get_metering();
}

// ---------------------------------------------------------------------------
// transcribe_session
// ---------------------------------------------------------------------------

std::string StorageManager::transcribe_session(const std::string& session_id,
                                               ProgressCallback progress) {
    // Retrieve all chunks from the database.
    std::vector<AudioChunk> chunks = db_.get_chunks(session_id);
    if (chunks.empty()) {
        db_.mark_failed(session_id);
        return "";
    }

    // Calculate total duration.
    int64_t total_duration_ms = 0;
    for (const auto& chunk : chunks) {
        total_duration_ms += chunk.duration_ms;
    }

    // Transcribe each chunk and concatenate.
    std::string full_transcript;
    float chunk_weight = 1.0f / static_cast<float>(chunks.size());

    for (size_t i = 0; i < chunks.size(); ++i) {
        const auto& chunk = chunks[i];

        // Write chunk blob to a temporary M4A file for the converter.
        std::string tmp_path = data_dir_ + "/tmp_chunk_" + session_id
                               + "_" + std::to_string(chunk.chunk_index) + ".m4a";
        {
            std::ofstream out(tmp_path, std::ios::binary);
            if (!out.is_open()) continue;
            out.write(reinterpret_cast<const char*>(chunk.audio_data.data()),
                      static_cast<std::streamsize>(chunk.audio_data.size()));
        }

        // Convert M4A to PCM at 16 kHz for whisper.
        std::vector<float> pcm = converter_.m4a_to_pcm(tmp_path, 16000);

        // Clean up temp file.
        std::filesystem::remove(tmp_path);

        if (pcm.empty()) continue;

        // Create a per-chunk progress callback that maps to the overall range.
        ProgressCallback chunk_progress;
        if (progress) {
            float base = static_cast<float>(i) * chunk_weight;
            chunk_progress = [progress, base, chunk_weight](float p) {
                progress(base + p * chunk_weight);
            };
        }

        // Transcribe.
        std::string text = whisper_.transcribe(pcm, 16000, chunk_progress);
        if (!text.empty()) {
            if (!full_transcript.empty()) {
                full_transcript += " ";
            }
            full_transcript += text;
        }
    }

    // Persist the result.
    if (full_transcript.empty()) {
        db_.mark_failed(session_id);
    } else {
        db_.update_transcript(session_id, full_transcript, total_duration_ms);
    }

    // Signal 100% progress.
    if (progress) progress(1.0f);

    return full_transcript;
}

// ---------------------------------------------------------------------------
// Data access (delegates)
// ---------------------------------------------------------------------------

std::vector<RecordingSession> StorageManager::get_sessions() const {
    return db_.get_sessions();
}

std::optional<RecordingSession> StorageManager::get_session(
    const std::string& id) const {
    return db_.get_session(id);
}

bool StorageManager::delete_session(const std::string& id) {
    // Also remove chunk files from disk.
    std::string session_dir = data_dir_ + "/" + id;
    if (std::filesystem::exists(session_dir)) {
        std::filesystem::remove_all(session_dir);
    }

    return db_.delete_session(id);
}

// ---------------------------------------------------------------------------
// recover_orphaned_sessions
// ---------------------------------------------------------------------------

void StorageManager::recover_orphaned_sessions() {
    std::vector<RecordingSession> orphaned = db_.get_orphaned_sessions();

    for (const auto& session : orphaned) {
        // Try to transcribe whatever chunks were saved before the crash.
        std::vector<AudioChunk> chunks = db_.get_chunks(session.id);

        if (chunks.empty()) {
            // No chunks saved — mark as failed.
            db_.mark_failed(session.id);
            continue;
        }

        // Mark as transcribing, then attempt transcription.
        db_.update_status(session.id, RecordingStatus::transcribing);

        std::string transcript = transcribe_session(session.id);
        // transcribe_session already updates the DB on success/failure.
        (void)transcript;
    }
}

} // namespace vr
