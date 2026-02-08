#include "WhisperEngine.hpp"

#include <algorithm>
#include <cmath>
#include <stdexcept>

#include "whisper.h"

namespace vr {

// ---------------------------------------------------------------------------
// Construction / destruction
// ---------------------------------------------------------------------------

WhisperEngine::WhisperEngine() = default;

WhisperEngine::~WhisperEngine() {
    std::lock_guard<std::mutex> lock(mu_);
    if (ctx_) {
        whisper_free(ctx_);
        ctx_ = nullptr;
    }
}

WhisperEngine::WhisperEngine(WhisperEngine&& other) noexcept {
    std::lock_guard<std::mutex> lock(other.mu_);
    ctx_ = other.ctx_;
    other.ctx_ = nullptr;
}

WhisperEngine& WhisperEngine::operator=(WhisperEngine&& other) noexcept {
    if (this != &other) {
        std::lock_guard<std::mutex> lk1(mu_);
        std::lock_guard<std::mutex> lk2(other.mu_);
        if (ctx_) {
            whisper_free(ctx_);
        }
        ctx_ = other.ctx_;
        other.ctx_ = nullptr;
    }
    return *this;
}

// ---------------------------------------------------------------------------
// init
// ---------------------------------------------------------------------------

bool WhisperEngine::init(const std::string& model_path) {
    std::lock_guard<std::mutex> lock(mu_);

    if (ctx_) {
        whisper_free(ctx_);
        ctx_ = nullptr;
    }

    struct whisper_context_params cparams = whisper_context_default_params();
    cparams.use_gpu = true;  // Metal on Apple Silicon

    ctx_ = whisper_init_from_file_with_params(model_path.c_str(), cparams);
    if (!ctx_) {
        return false;
    }
    return true;
}

// ---------------------------------------------------------------------------
// is_loaded
// ---------------------------------------------------------------------------

bool WhisperEngine::is_loaded() const {
    std::lock_guard<std::mutex> lock(mu_);
    return ctx_ != nullptr;
}

// ---------------------------------------------------------------------------
// transcribe
// ---------------------------------------------------------------------------

std::string WhisperEngine::transcribe(const std::vector<float>& audio_data,
                                      int sample_rate,
                                      ProgressCallback progress) {
    std::lock_guard<std::mutex> lock(mu_);

    if (!ctx_) {
        return "";
    }

    // 1. Resample to 16 kHz if necessary.
    std::vector<float> pcm16k;
    if (sample_rate != 16000) {
        pcm16k = resample_to_16k(audio_data, sample_rate);
    } else {
        pcm16k = audio_data;
    }

    if (pcm16k.empty()) {
        return "";
    }

    // Configure whisper parameters
    whisper_full_params params = whisper_full_default_params(WHISPER_SAMPLING_GREEDY);
    params.print_progress   = false;
    params.print_timestamps = false;
    params.single_segment   = false;
    params.language         = "en";
    params.n_threads        = 4;

    // Wire up progress callback
    struct CallbackCtx { ProgressCallback cb; };
    CallbackCtx cb_ctx{progress};
    params.progress_callback = [](struct whisper_context* /*ctx*/,
                                  struct whisper_state* /*state*/,
                                  int progress_pct,
                                  void* user_data) {
        auto* c = static_cast<CallbackCtx*>(user_data);
        if (c->cb) {
            c->cb(static_cast<float>(progress_pct) / 100.0f);
        }
    };
    params.progress_callback_user_data = &cb_ctx;

    // Run inference
    int ret = whisper_full(ctx_, params, pcm16k.data(),
                           static_cast<int>(pcm16k.size()));
    if (ret != 0) {
        return "";
    }

    // Collect segments
    std::string result;
    int n_segments = whisper_full_n_segments(ctx_);
    for (int i = 0; i < n_segments; ++i) {
        const char* text = whisper_full_get_segment_text(ctx_, i);
        if (text) {
            result += text;
        }
    }
    return result;
}

// ---------------------------------------------------------------------------
// resample_to_16k  (simple linear interpolation — good enough for speech)
// ---------------------------------------------------------------------------

std::vector<float> WhisperEngine::resample_to_16k(const std::vector<float>& input,
                                                   int in_rate) const {
    if (input.empty() || in_rate <= 0) {
        return {};
    }

    constexpr int kTargetRate = 16000;
    const double ratio = static_cast<double>(kTargetRate) / static_cast<double>(in_rate);
    const size_t out_len = static_cast<size_t>(
        std::ceil(static_cast<double>(input.size()) * ratio));

    std::vector<float> output(out_len);

    for (size_t i = 0; i < out_len; ++i) {
        double src_idx = static_cast<double>(i) / ratio;
        size_t idx0 = static_cast<size_t>(src_idx);
        size_t idx1 = std::min(idx0 + 1, input.size() - 1);
        double frac = src_idx - static_cast<double>(idx0);
        output[i] = static_cast<float>(
            input[idx0] * (1.0 - frac) + input[idx1] * frac);
    }

    return output;
}

} // namespace vr
