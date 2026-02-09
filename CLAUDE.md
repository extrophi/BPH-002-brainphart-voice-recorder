# BrainPh.art Voice Recorder — Agent Instructions

## What This Is

**BrainPhart Voice** — Local privacy-first voice transcriber for macOS.
Bundle ID: `art.brainph.voice` | Version: 0.2.0

Records audio via AVAudioEngine (16kHz mono PCM), transcribes locally via whisper.cpp with Metal GPU, auto-pastes transcript to cursor. Zero network calls. Zero telemetry.

---

## Architecture

### Three-Layer Stack

```
┌─────────────────────────────────────────┐
│  Swift UI Layer (VoiceRecorder/)        │
│  SwiftUI views, AppState (@MainActor),  │
│  AudioManager (AVAudioEngine),          │
│  FloatingOverlay (NSPanel)              │
├─────────────────────────────────────────┤
│  Obj-C++ Bridge (VoiceRecorderBridge/)  │
│  WhisperBridge, StorageBridge           │
│  Thread-safe callbacks to main queue    │
├─────────────────────────────────────────┤
│  C++ Core (VoiceRecorderCore/)          │
│  WhisperEngine, DatabaseManager,        │
│  AudioConverter (legacy FFmpeg)         │
│  Static lib: libVoiceRecorderCore.a     │
└─────────────────────────────────────────┘
```

### Key Architectural Decisions

1. **Pure Swift recording (NOT C++ FFmpeg)**
   - AudioManager.swift uses AVAudioEngine directly
   - Records 16kHz mono Float32 PCM (Whisper-native format)
   - No sample rate conversion needed, no M4A encoding/decoding
   - Old AudioRecorder.cpp/StorageManager.cpp removed from CMake build

2. **Direct PCM transcription path**
   - `WhisperBridge.transcribePCMData:` takes raw Float32 bytes
   - Bypasses AudioConverter/file I/O entirely
   - Recording → SQLite chunks → concatenated PCM → whisper.cpp

3. **35-second streaming chunks**
   - AudioManager splits recording into 35s PCM chunks
   - Each chunk stored in SQLite immediately via StorageBridge
   - Maximum data loss on crash: 35 seconds

4. **Thread-safe AudioBuffer**
   - Separate `@unchecked Sendable` class with NSLock
   - Audio render thread writes → main thread reads
   - Required because @MainActor classes can't have nonisolated mutating methods

5. **NSPanel floating window**
   - `.floating` level + `.canJoinAllSpaces` + `hidesOnDeactivate = false`
   - Non-activating: never steals focus from user's current app
   - Global hotkey: Cmd+Shift+Space toggles recording

---

## Build Commands

### Step 1: Build C++ static library
```bash
cd /Users/kjd/01-projects/BPH-002-brainphart-voice-recorder
cmake -B build -DCMAKE_BUILD_TYPE=Release -DWHISPER_METAL=ON
cmake --build build -j
```

### Step 2: Build Swift app
```bash
swift build -c release 2>&1
```

### Step 3: Verify build
```bash
# Must exit 0 with no errors
swift build -c release 2>&1 | grep -c "error:"
# Expected output: 0
```

### Step 4: Package DMG (optional)
```bash
bash Scripts/create-dmg.sh
```

**IMPORTANT:** Always rebuild the C++ static lib first, then Swift. The Swift build links against `build/libVoiceRecorderCore.a`.

---

## Directory Structure

```
Sources/
├── VoiceRecorder/                  # Swift UI layer
│   ├── VoiceRecorderApp.swift      # Entry point, hotkey, model loading
│   ├── AppState.swift              # @MainActor state machine (337 lines)
│   ├── AudioManager.swift          # AVAudioEngine 16kHz PCM recording (295 lines)
│   ├── Config.swift                # Centralized config, model path resolution
│   ├── FloatingOverlay.swift       # NSPanel floating window (273 lines)
│   ├── ContentView.swift           # Main window with history
│   ├── HistoryView.swift           # Session list sidebar
│   ├── WaveformView.swift          # Canvas waveform visualization
│   └── AutoPaste.swift             # CGEvent-based Cmd+V simulation
│
├── VoiceRecorderBridge/            # Obj-C++ bridge
│   ├── WhisperBridge.h/.mm         # whisper.cpp wrapper (PCM + legacy M4A paths)
│   ├── StorageBridge.h/.mm         # DatabaseManager wrapper
│   └── VoiceRecorderBridge.h       # Umbrella header
│
├── VoiceRecorderCore/              # C++ core (static lib)
│   ├── WhisperEngine.hpp/.cpp      # whisper.cpp thin wrapper (Metal GPU)
│   ├── AudioConverter.hpp/.cpp     # M4A→PCM via FFmpeg (LEGACY, still needed for playback)
│   ├── DatabaseManager.hpp/.cpp    # SQLite WAL persistence
│   ├── Types.hpp                   # Shared enums/structs
│   └── module.modulemap            # Clang module map
│
├── docs/                           # Fetched documentation (caveman-docs)
└── Resources/models/               # ggml-base.en.bin whisper model
```

### Dead code (NOT compiled, NOT in CMake):
- `StorageManager.cpp/.hpp` — old orchestrator, replaced by AppState.swift
- `AudioRecorder.cpp/.hpp` — old FFmpeg recorder, replaced by AudioManager.swift

---

## Current Docs

**READ THESE BEFORE WRITING CODE.** Located in `docs/`:

Documentation is fetched by caveman-docs before each job. If docs/ is empty or missing for a topic you need, request a doc fetch.

---

## Recording Flow (Complete Pipeline)

```
User presses Cmd+Shift+Space
    → AppState.toggleRecording()
    → AppState.startRecording()
        → StorageBridge.createSession() → UUID
        → AudioManager.startRecording()
            → AVAudioEngine.inputNode.installTap()
            → Converts native format → 16kHz mono Float32
            → Accumulates in AudioBuffer (NSLock-protected)
            → Every 35 seconds: fires onChunkComplete callback
                → AppState receives chunk
                → StorageBridge.addChunk(data, sessionId, index)
        → Metering timer (50ms): polls AudioManager.getMeteringLevel()
        → Elapsed timer (1s): increments recordingElapsedSeconds

User presses Cmd+Shift+Space again
    → AppState.stopRecording()
        → AudioManager.stopRecording()
            → Flushes final partial chunk
        → AppState.transcribeActiveSession()
            → StorageBridge.getAudioForSession() → concatenated PCM Data
            → WhisperBridge.transcribePCMData(data, 16000, progress, completion)
                → Background serial queue
                → WhisperEngine.transcribe(pcm_float_array)
                    → whisper_full() with Metal GPU
                    → Progress callbacks → main queue
                → Completion → main queue
            → StorageBridge.updateTranscript(text, sessionId)
            → AutoPaste.pasteText(text) → clipboard + CGEvent Cmd+V
            → Reload session list
```

---

## Known Pitfalls

> Lessons from $8+ and 130+ turns of previous failed jobs. DO NOT repeat these.

### Audio
- **AVAudioConverter status bugs:** The `status` property after conversion can report misleading values. Always check the actual output buffer length, not just the status enum.
- **Interleaved format mismatch:** AVAudioEngine tap delivers non-interleaved buffers. AVAudioConverter input format must match exactly. Use `AVAudioFormat(commonFormat:sampleRate:channels:interleaved:)` with `interleaved: false`.
- **WAV header for Float32:** Use `audioFormat = 3` (IEEE float), NOT `1` (PCM integer). Getting this wrong produces static/noise on playback.
- **AudioManager chunk boundary:** The 35-second chunk split happens in the audio tap callback. Off-by-one errors here cause data gaps or duplicated samples.

### Transcription
- **Model path resolution is complex:** Binary runs from `.build/release/` which is 4+ levels deep. Bundle.main paths WILL NOT WORK in SPM executables. Config.swift walks up from the executable path checking 9 candidate locations.
- **Silent failures:** If whisper model fails to load, transcription silently returns empty string. ALWAYS check `isModelLoaded` before attempting transcription and surface errors to UI.

### UI
- **NSPanel hidesOnDeactivate:** MUST be `false`. If `true`, the floating overlay disappears when the app loses focus — which is the primary use case.
- **NSHostingController transparency:** The hosting controller's view must also have a clear background. Setting only the panel background to `.clear` is not enough.
- **becomesKeyOnlyIfNeeded:** Must be `true` on the NSPanel. Otherwise clicking the overlay steals focus from the user's active app.

### Build System
- **Rebuild static lib first:** Swift linker uses stale `.a` file if you don't rebuild CMake first.
- **macOS version warnings are cosmetic:** Static libs built for newer macOS show warnings but work fine.
- **module.modulemap must match compiled sources:** If you remove a .cpp/.hpp from CMake, also remove its header from the modulemap. Stale modulemap entries cause build failures.
- **FFmpeg still needed:** AudioConverter.cpp uses FFmpeg for legacy M4A decoding. Cannot remove FFmpeg libs from Package.swift until M4A support is fully removed.

### Anti-Patterns From Failed Jobs
- Agent "simplified" by removing features when encountering compiler errors
- Agent used training data for AVAudioConverter API instead of checking current docs
- Agent stubbed out error handling with empty catch blocks
- Agent edited same file 10+ times without building (thrashing)
- Agent never ran `swift build` to verify changes compiled

---

## What NOT To Do

- Do NOT code from training data — read the docs in `docs/` first
- Do NOT simplify or stub features when you hit errors — fix the root cause
- Do NOT skip `swift build` before declaring done
- Do NOT use WhisperKit or SwiftWhisper wrapper libraries
- Do NOT buffer entire recordings in RAM — use the 35s chunk architecture
- Do NOT hard-code file paths
- Do NOT add network calls or telemetry
- Do NOT remove error handling or use empty catch blocks
- Do NOT edit a file without reading it first
- Do NOT edit the same file more than 5 times without building to verify

---

## Verification Checklist

Before declaring ANY job complete:

1. `swift build -c release 2>&1` — ZERO errors
2. All files you modified still exist and are non-empty
3. No features removed from what was requested
4. Error messages surface to UI (check `AppState.errorMessage` is set on failures)
5. Any new code has proper error handling (no empty catch blocks)

---

**This is crisis intervention infrastructure. Build it like lives depend on it.**
