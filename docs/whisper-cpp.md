# whisper.cpp C API Reference (Fetched: 2026-02-09)

## Version
- **Latest**: Main branch (actively maintained)
- **Repository**: [ggml-org/whisper.cpp](https://github.com/ggml-org/whisper.cpp)
- **Status**: Production-ready, ~3,965 commits, multiple platform support

---

## Core Concepts

whisper.cpp is a lightweight C/C++ port of OpenAI's Whisper speech-to-text model. The high-level C-style API is implemented in `whisper.h`/`whisper.cpp`. Key features:
- Zero memory allocations at runtime (efficient for real-time processing)
- Multi-platform: iOS, Android, macOS, Linux, Windows, WebAssembly, Raspberry Pi
- GPU acceleration: Metal (macOS/iOS), CUDA (NVIDIA), Core ML (Apple Neural Engine)
- Streaming and parallel processing support

---

## 1. Model Initialization

### Basic Initialization with Parameters (Recommended)

```c
#include <whisper.h>

// Initialize context parameters
struct whisper_context_params cparams = whisper_context_default_params();
cparams.use_gpu = true;          // Enable GPU (Metal on macOS)
cparams.gpu_device = 0;          // GPU device index (0 for single GPU)

// Load model
struct whisper_context * ctx = whisper_init_from_file_with_params(
    "/path/to/ggml-base.en.bin",
    cparams
);

if (ctx == NULL) {
    fprintf(stderr, "Failed to load model\n");
    return -1;
}
```

### Context Parameters Structure

```c
struct whisper_context_params {
    bool  use_gpu;                // Enable GPU acceleration
    bool  flash_attn;             // Flash attention (experimental)
    int   gpu_device;             // CUDA device selection
    bool  dtw_token_timestamps;   // Dynamic Time Warping timestamps
    enum  whisper_alignment_heads_preset dtw_aheads_preset;
    int   dtw_n_top;
    struct whisper_aheads dtw_aheads;
    size_t dtw_mem_size;
};
```

### Alternative Initialization Methods

```c
// From buffer (e.g., embedded model)
struct whisper_context * ctx = whisper_init_from_buffer_with_params(
    buffer_data, buffer_size, cparams
);

// Without pre-allocated state (for manual control)
struct whisper_context * ctx = whisper_init_from_file_with_params_no_state(
    model_path, cparams
);
// Then allocate state manually:
struct whisper_state * state = whisper_init_state(ctx);
```

---

## 2. Configuration & Parameters

### Full Transcription Parameters

```c
struct whisper_full_params params = whisper_full_default_params(
    WHISPER_SAMPLING_GREEDY
);

// Audio processing
params.n_threads = 4;            // CPU threads (match your core count)
params.offset_ms = 0;            // Skip first N milliseconds
params.duration_ms = 0;          // Transcribe first N ms (0 = all)

// Language & translation
params.language = "en";          // BCP-47 language code (NULL = auto-detect)
params.translate = false;        // Translate to English if false

// Output control
params.single_segment = false;   // Output single merged segment
params.no_timestamps = false;    // Include timestamp tokens
params.no_context = false;       // Use context tokens

// Decoding strategy
params.strategy = WHISPER_SAMPLING_GREEDY;
params.n_max_text_ctx = 16384;   // Maximum tokens

// Temperature (quality vs diversity)
params.temperature = 0.0f;       // 0.0 = deterministic
params.temperature_inc = 0.2f;   // Increment if no progress

// Beam search (if WHISPER_SAMPLING_BEAM_SEARCH)
params.beam_size = 5;
params.patience = 1.0f;

// Sampling thresholds
params.entropy_thold = 2.4f;     // Skip tokens with low entropy
params.logprob_thold = -1.0f;    // Skip tokens with low log probability
params.thold_pt = 0.01f;         // Probability threshold (token timestamps)
params.thold_ptsum = 0.01f;      // Cumulative probability sum threshold

// Special features
params.token_timestamps = false; // Per-token timestamps
params.suppress_regex = NULL;    // Suppress tokens matching regex
params.suppress_blank = true;    // Skip silence tokens
params.suppress_nst = false;     // Skip non-speech tokens
```

### Sampling Strategies

- **WHISPER_SAMPLING_GREEDY**: Single best token per step (OpenAI's GreedyDecoder)
- **WHISPER_SAMPLING_BEAM_SEARCH**: Beam search with configurable width (OpenAI's BeamSearchDecoder)

---

## 3. Main Transcription Function

```c
// Core function signature
int whisper_full(
    struct whisper_context * ctx,
    struct whisper_full_params params,
    const float * samples,
    int n_samples
);

// Returns 0 on success, non-zero on error
```

### Example: Transcribe Float Array

```c
// Assume audio is 16kHz mono PCM, normalized to [-1.0, 1.0]
float * audio_buffer = ...;     // Your PCM audio samples
int n_samples = 48000;          // 3 seconds at 16kHz

struct whisper_full_params params = whisper_full_default_params(
    WHISPER_SAMPLING_GREEDY
);
params.n_threads = 4;
params.language = "en";

// Run transcription
int result = whisper_full(ctx, params, audio_buffer, n_samples);
if (result != 0) {
    fprintf(stderr, "Transcription failed: %d\n", result);
    return -1;
}

// Process results (see section 4)
```

### Advanced: With State Management

```c
struct whisper_state * state = whisper_init_state(ctx);

int result = whisper_full_with_state(
    ctx, state, params, audio_samples, n_samples
);

// Reuse state for multiple transcriptions
// (avoids repeated memory allocation)

whisper_state_free(state);
```

---

## 4. Retrieving Results

### Segment Iteration

```c
int n_segments = whisper_full_n_segments(ctx);

for (int i = 0; i < n_segments; i++) {
    // Text of segment
    const char * text = whisper_full_get_segment_text(ctx, i);

    // Timestamps (in 10ms units)
    int64_t t0 = whisper_full_get_segment_t0(ctx, i);
    int64_t t1 = whisper_full_get_segment_t1(ctx, i);

    printf("[%02lld:%02lld --> %02lld:%02lld] %s\n",
        t0 / 6000, (t0 % 6000) / 100,
        t1 / 6000, (t1 % 6000) / 100,
        text
    );
}
```

### Token-Level Access (Advanced)

```c
// Get tokens for a segment
int n_tokens = whisper_full_n_tokens(ctx, segment_idx);

for (int j = 0; j < n_tokens; j++) {
    whisper_token_data token = whisper_full_get_token_data(
        ctx, segment_idx, j
    );
    // token.id, token.tid, token.p (probability), token.t0, token.t1
}
```

---

## 5. Callbacks & Progress

### Progress Callback

```c
void progress_callback(
    struct whisper_context * ctx,
    struct whisper_state * state,
    int progress,           // 0-100
    void * user_data
) {
    int * pctx = (int *)user_data;
    printf("Progress: %d%%\n", progress);
}

// Attach to params
params.progress_callback = progress_callback;
params.progress_callback_user_data = NULL;  // or pointer to user data
```

### New Segment Callback (Real-Time Results)

```c
void new_segment_callback(
    struct whisper_context * ctx,
    struct whisper_state * state,
    int n_new,              // Number of new segments
    void * user_data
) {
    // Called whenever new segments are decoded
    // Enables real-time output without waiting for full transcription

    int n_total = whisper_full_n_segments(ctx);
    const char * text = whisper_full_get_segment_text(
        ctx, n_total - 1
    );
    printf("New segment: %s\n", text);
}

params.new_segment_callback = new_segment_callback;
params.new_segment_callback_user_data = NULL;
```

### Encoder Begin Callback (Advanced Streaming)

```c
bool encoder_begin_callback(
    struct whisper_context * ctx,
    struct whisper_state * state,
    void * user_data
) {
    // Called before encoder runs
    // Return false to abort transcription
    return true;
}

params.encoder_begin_callback = encoder_begin_callback;
params.encoder_begin_callback_user_data = NULL;
```

---

## 6. GPU Acceleration (macOS)

### Metal Acceleration

Metal is the primary GPU option for Apple Silicon (M-series) and Intel Macs.

**Compile with Metal:**
```bash
cmake -B build -DWHISPER_METAL=ON
cmake --build build
```

**Enable at Runtime:**
```c
struct whisper_context_params cparams = whisper_context_default_params();
cparams.use_gpu = true;  // Metal automatically selected on macOS
```

**Performance**: Metal encoder runs fully on GPU, delivering **3x+ speed improvements** vs CPU.

### Core ML (Apple Neural Engine)

For Apple Neural Engine (ANE) support on Apple Silicon:

```bash
cmake -B build -DWHISPER_COREML=ON
cmake --build build
```

**Requirements:**
- macOS Sonoma (14.0+) recommended
- Python 3.11+ for model compilation
- First run compiles model to device-optimized format; subsequent runs use cached version

**Integration:**
```c
// After standard initialization with use_gpu=true
// Check if Core ML encoder is available:
// (No explicit API; uses Core ML encoder if compiled with COREML flag)
```

### CUDA (NVIDIA)

```bash
cmake -B build -DWHISPER_CUDA=ON
cmake --build build
```

```c
struct whisper_context_params cparams = whisper_context_default_params();
cparams.use_gpu = true;
cparams.gpu_device = 0;  // Select CUDA device
```

---

## 7. Thread Safety & Concurrency

### Thread Safety Rules

1. **Context Creation**: Thread-safe. Each thread can call `whisper_init_*()`.
2. **State Objects**: NOT thread-safe. Each transcription requires its own `whisper_state`.
3. **Read-Only Access**: `whisper_full_get_segment_*()` calls are safe after transcription completes.

### Parallel Transcription Pattern

```c
// Single context, multiple states
struct whisper_context * ctx = whisper_init_from_file_with_params(
    model_path, cparams
);

// Thread 1
struct whisper_state * state1 = whisper_init_state(ctx);
whisper_full_with_state(ctx, state1, params, samples1, n1);

// Thread 2 (simultaneously safe)
struct whisper_state * state2 = whisper_init_state(ctx);
whisper_full_with_state(ctx, state2, params, samples2, n2);

// Clean up
whisper_state_free(state1);
whisper_state_free(state2);
```

### Alternative: `whisper_full_parallel()`

```c
// Distributed parallel processing (experimental)
int n_processors = 4;
int result = whisper_full_parallel(
    ctx, params, audio_samples, n_samples,
    n_processors
);
```

---

## 8. Cleanup

```c
// After transcription complete
whisper_free(ctx);  // Frees context and associated state
```

---

## 9. Complete Example: Float PCM Transcription

```c
#include <stdio.h>
#include <whisper.h>

int main(int argc, char * argv[]) {
    // Load model
    struct whisper_context_params cparams = whisper_context_default_params();
    cparams.use_gpu = true;

    struct whisper_context * ctx = whisper_init_from_file_with_params(
        "models/ggml-base.en.bin", cparams
    );
    if (!ctx) {
        fprintf(stderr, "Failed to load model\n");
        return 1;
    }

    // Prepare parameters
    struct whisper_full_params params = whisper_full_default_params(
        WHISPER_SAMPLING_GREEDY
    );
    params.n_threads = 4;
    params.language = "en";
    params.print_progress = false;

    // Load or generate float audio (16kHz mono)
    float * samples = NULL;
    int n_samples = 0;
    // ... load from file or audio device ...

    // Transcribe
    if (whisper_full(ctx, params, samples, n_samples) != 0) {
        fprintf(stderr, "Transcription failed\n");
        return 1;
    }

    // Output results
    int n_segments = whisper_full_n_segments(ctx);
    for (int i = 0; i < n_segments; i++) {
        int64_t t0 = whisper_full_get_segment_t0(ctx, i);
        int64_t t1 = whisper_full_get_segment_t1(ctx, i);
        const char * text = whisper_full_get_segment_text(ctx, i);

        printf("[%02lld:%05.2f] %s\n",
            t0 / 6000, (t0 % 6000) / 100.0f, text
        );
    }

    // Cleanup
    whisper_free(ctx);
    free(samples);

    return 0;
}
```

---

## 10. Key Differences: Greedy vs Beam Search

| Feature | Greedy | Beam Search |
|---------|--------|-------------|
| **Speed** | Fastest | Slower (configurable) |
| **Quality** | Good for clear audio | Better for noisy audio |
| **Memory** | Low | Higher (beam_size × context) |
| **Key Param** | `temperature` | `beam_size`, `patience` |
| **Use Case** | Real-time, streaming | Offline batch (small audio) |

---

## 11. Common Patterns

### Streaming Transcription
Use `params.offset_ms` and `params.duration_ms` to process audio in chunks. Combine with `new_segment_callback` for real-time output.

### Language Auto-Detection
Set `params.language = NULL` and `params.detect_language = true` to auto-detect language.

### Suppress Noise
Increase `params.entropy_thold` (default 2.4) to suppress low-confidence tokens in noisy audio.

### Custom VAD (Voice Activity Detection)
Use `params.vad` and `params.vad_model_path` to integrate external VAD pre-processing (experimental).

---

## Sources

- [ggml-org/whisper.cpp GitHub Repository](https://github.com/ggml-org/whisper.cpp)
- [whisper.h Header File](https://github.com/ggml-org/whisper.cpp/blob/master/include/whisper.h)
- [Metal GPU Acceleration Discussion](https://github.com/ggml-org/whisper.cpp/discussions/681)
- [Core ML Integration Guide](https://github.com/ggml-org/whisper.cpp)
- [Streaming Audio Examples](https://github.com/ggml-org/whisper.cpp/tree/master/examples)
