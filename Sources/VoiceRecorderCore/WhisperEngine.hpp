#pragma once

#include "Types.hpp"
#include <memory>
#include <mutex>
#include <string>
#include <vector>

namespace vr {

/// Thin wrapper around whisper.cpp's C API.
/// Loads a ggml model once, then transcribes PCM audio buffers on demand.
class WhisperEngine {
public:
    WhisperEngine();
    ~WhisperEngine();

    // Non-copyable, movable.
    WhisperEngine(const WhisperEngine&) = delete;
    WhisperEngine& operator=(const WhisperEngine&) = delete;
    WhisperEngine(WhisperEngine&&) noexcept;
    WhisperEngine& operator=(WhisperEngine&&) noexcept;

    /// Load the ggml model file (e.g. "ggml-base.en.bin").
    /// Returns true on success.  Thread-safe.
    bool init(const std::string& model_path);

    /// Transcribe raw PCM float32 audio.
    /// @param audio_data  Interleaved float32 samples (mono).
    /// @param sample_rate Source sample rate (will be resampled to 16 kHz internally).
    /// @param progress    Optional callback fired with progress 0.0-1.0.
    /// @return  Transcribed text, or empty string on failure.
    std::string transcribe(const std::vector<float>& audio_data,
                           int sample_rate,
                           ProgressCallback progress = nullptr);

    /// Whether a model has been successfully loaded.
    bool is_loaded() const;

private:
    /// Resample from `in_rate` to 16 kHz (whisper's native rate).
    std::vector<float> resample_to_16k(const std::vector<float>& input,
                                       int in_rate) const;

    struct whisper_context* ctx_ = nullptr;   // opaque whisper.h handle
    mutable std::mutex      mu_;
};

} // namespace vr
