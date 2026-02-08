#pragma once

#include <string>
#include <vector>

namespace vr {

/// Converts audio between formats using FFmpeg's libavcodec / libswresample.
/// Primary use-case: decode M4A chunk files to float32 PCM at 16 kHz for
/// whisper.cpp inference.
class AudioConverter {
public:
    AudioConverter();
    ~AudioConverter();

    // Non-copyable.
    AudioConverter(const AudioConverter&) = delete;
    AudioConverter& operator=(const AudioConverter&) = delete;

    /// Decode an M4A (AAC) file on disk to float32 PCM at the given sample
    /// rate.  Returns an empty vector on failure.
    std::vector<float> m4a_to_pcm(const std::string& input_path,
                                  int target_sample_rate = 16000) const;

    /// Resample raw float32 PCM data from one rate to another.
    /// Uses FFmpeg's libswresample for high-quality conversion.
    static std::vector<float> resample(const std::vector<float>& input_data,
                                       int input_rate,
                                       int output_rate);
};

} // namespace vr
