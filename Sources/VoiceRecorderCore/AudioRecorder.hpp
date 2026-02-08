#pragma once

#include "Types.hpp"
#include <atomic>
#include <memory>
#include <mutex>
#include <string>
#include <thread>

namespace vr {

/// Records audio from the default microphone using FFmpeg's libavdevice
/// (AVFoundation input on macOS).
///
/// Architecture: 35-second burst chunks.  Every 35 seconds the current M4A
/// file is finalized and a new one is started.  Each chunk is a complete,
/// self-contained M4A file written to disk.
class AudioRecorder {
public:
    AudioRecorder();
    ~AudioRecorder();

    // Non-copyable.
    AudioRecorder(const AudioRecorder&) = delete;
    AudioRecorder& operator=(const AudioRecorder&) = delete;

    /// Start recording to the given base directory.
    /// Files are written as <output_dir>/<session_id>_chunk_<N>.m4a.
    /// @param output_dir  Directory for chunk files (must exist).
    /// @param session_id  Used as a filename prefix.
    /// @param burst_cb    Called on the recording thread when a chunk is done.
    /// @param meter_cb    Called periodically with the current audio level.
    /// @return true on success.
    bool start_recording(const std::string& output_dir,
                         const std::string& session_id,
                         BurstCallback burst_cb = nullptr,
                         MeteringCallback meter_cb = nullptr);

    /// Stop the current recording.
    /// Finalizes the last chunk and returns the path to it.
    /// Returns empty string if nothing was recording.
    std::string stop_recording();

    /// Current audio level in [0.0, 1.0].  Thread-safe.
    float get_metering() const;

    /// Whether we are currently recording.
    bool is_recording() const;

    /// Number of completed chunks in this session so far.
    int chunk_count() const;

private:
    /// Background thread entry point.
    void recording_loop();

    /// Finalize the current M4A chunk, invoke burst callback.
    void finalize_chunk();

    /// Open a new M4A output file for the next chunk.
    bool open_new_chunk();

    /// Compute RMS level from a buffer of PCM samples.
    static float compute_rms(const float* samples, size_t count);

    // ---- State ----
    std::atomic<bool>   recording_{false};
    std::thread         record_thread_;
    mutable std::mutex  mu_;

    // Callbacks.
    BurstCallback       burst_cb_;
    MeteringCallback    meter_cb_;

    // Session info.
    std::string         output_dir_;
    std::string         session_id_;
    int                 chunk_index_ = 0;
    std::string         current_chunk_path_;

    // Audio level (written by recording thread, read by UI).
    std::atomic<float>  current_level_{0.0f};

    // Burst timing.
    static constexpr int kBurstDurationSec = 35;
    static constexpr int kSampleRate       = 44100;
    static constexpr int kChannels         = 1;   // mono

    // FFmpeg opaque handles — typed as void* to avoid including FFmpeg
    // headers in the public interface.
    void* fmt_ctx_in_  = nullptr;   // AVFormatContext* (input / capture)
    void* fmt_ctx_out_ = nullptr;   // AVFormatContext* (output / muxer)
    void* codec_ctx_   = nullptr;   // AVCodecContext*  (AAC encoder)
    void* swr_ctx_     = nullptr;   // SwrContext*      (sample format conversion)
};

} // namespace vr
