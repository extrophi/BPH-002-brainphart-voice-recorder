# Technical Proposal: VoiceRecorder — macOS Native (Fresh Start)

## Context
SuperWhisper replacement. Crisis intervention voice recorder. macOS M2 native, whisper.cpp + FFmpeg, 100% local. Previous iOS attempt is dead — nuking repo and starting clean.

## Step 0: Repo Cleanup
1. **Rename GitHub repo** — `gh repo rename` (need your preferred name)
2. **Remove all old tracked files** — `git rm -rf` everything except `PRD/` and `.gitignore`
3. **Move `PRD/claude.md` → `CLAUDE.md`** at project root (so Claude Code loads it automatically)
4. **Clean commit** as new baseline

## Architecture (Per PRD)
```
SwiftUI (Interface)
    ↓
Objective-C++ Bridge
    ↓
C++ Core (whisper.cpp + FFmpeg)
    ↓
M2 Metal Acceleration
```

### Stack
- **whisper.cpp** — git submodule, compiled from source with Metal, base.en model
- **FFmpeg** — compiled from source (static libs), bundled in app. **NOT Homebrew.**
- **SQLite** — system framework (macOS ships SQLite, no dependency needed)
- **Obj-C++ Bridge** — WhisperBridge, AudioBridge, StorageBridge
- **SwiftUI** — FloatingOverlay (NSPanel), HistoryWindow, Waveform
- **Storage** — SQLite database at `~/Library/Application Support/VoiceRecorder/voicerecorder.db`
  - Original 44.1kHz audio stored as BLOB (never lose the original)
  - Transcripts stored as TEXT
  - 16kHz resample is ephemeral (in-memory only, for whisper.cpp processing)
- **Recording** — 35-second burst architecture, immediate disk writes, crash recovery

### Dependency Management — NO HOMEBREW
All dependencies are pinned, versioned, and built from source. Nothing touches Homebrew.

**`dependencies.yaml`** (project root):
```yaml
dependencies:
  whisper.cpp:
    source: git_submodule
    repo: https://github.com/ggml-org/whisper.cpp.git
    version: v1.7.3  # pin to specific tag
    build: cmake -B build -DWHISPER_METAL=ON && cmake --build build -j

  ffmpeg:
    source: build_from_source
    repo: https://github.com/FFmpeg/FFmpeg.git
    version: "7.1"  # pin to specific release
    build_flags: >
      --enable-static --disable-shared
      --disable-programs --disable-doc
      --enable-libfdk-aac --enable-encoder=aac
      --enable-decoder=aac --enable-demuxer=mov
      --enable-muxer=ipod --enable-protocol=file
      --enable-filter=aresample
    output: static libs linked into app binary

  whisper_model:
    source: huggingface
    url: https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-base.en.bin
    sha256: <verify after download>
    size: 148MB
    location: Resources/models/ggml-base.en.bin

  sqlite:
    source: system  # macOS ships libsqlite3
    framework: libsqlite3.tbd
```

**`Scripts/setup.sh`** handles everything:
1. Init git submodules (whisper.cpp)
2. Clone + build FFmpeg from source (static libs)
3. Download whisper model from HuggingFace
4. Verify checksums
5. No Homebrew. No pip. No external package managers.

### Key Design Decisions (From PRD)
- 44.1kHz sample rate, mono, M4A format (recording + permanent storage)
- 16kHz mono float32 PCM (ephemeral, in-memory only, for whisper.cpp)
- **SQLite database** stores original 44.1kHz audio (BLOB) + transcripts (TEXT)
- 35-sec burst recording — each burst written to DB immediately
- No RAM buffering — write to disk continuously
- Atomic file operations everywhere
- FFmpeg built from source as static libs, bundled in DMG (not Homebrew)
- Obj-C++ bridge layer (not direct C bridging header)

### Database Schema
```sql
CREATE TABLE sessions (
    id TEXT PRIMARY KEY,
    created_at INTEGER NOT NULL,
    completed_at INTEGER,
    status TEXT DEFAULT 'recording',  -- recording | transcribing | complete | failed
    duration_ms INTEGER,
    transcript TEXT
);

CREATE TABLE chunks (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    session_id TEXT NOT NULL,
    chunk_index INTEGER NOT NULL,
    audio_blob BLOB NOT NULL,         -- Original 44.1kHz M4A
    duration_ms INTEGER,
    created_at INTEGER NOT NULL,
    FOREIGN KEY (session_id) REFERENCES sessions(id)
);
```

- Each 35-sec burst = 1 row in `chunks` with original 44.1kHz audio
- Session transcript stored in `sessions.transcript`
- Crash recovery: any session with `status='recording'` on launch = orphaned, re-process
- Audio playback: reconstruct from chunks (strip headers, concat PCM, re-wrap)
- Transcription: read chunk BLOBs → FFmpeg resample to 16kHz in memory → whisper.cpp

## File Structure
```
VoiceRecorder/
├── CLAUDE.md                            # Agent instructions (moved from PRD/)
├── PRD/
│   └── prd-v1.md                        # Product requirements
├── Dependencies/
│   └── whisper.cpp/                     # Git submodule
├── Resources/
│   └── models/
│       └── ggml-base.en.bin             # 142MB (gitignored)
├── Sources/
│   ├── VoiceRecorderCore/               # C++ core
│   │   ├── WhisperEngine.cpp/.hpp
│   │   ├── AudioRecorder.cpp/.hpp
│   │   ├── AudioConverter.cpp/.hpp
│   │   ├── StorageManager.cpp/.hpp
│   │   ├── DatabaseManager.cpp/.hpp     # SQLite operations
│   │   └── Types.hpp
│   ├── VoiceRecorderBridge/             # Obj-C++ bridge
│   │   ├── WhisperBridge.h/.mm
│   │   ├── AudioBridge.h/.mm
│   │   ├── StorageBridge.h/.mm
│   │   └── VoiceRecorderBridge.h
│   └── VoiceRecorder/                   # SwiftUI app
│       ├── App.swift
│       ├── AppState.swift
│       ├── FloatingOverlay.swift
│       ├── HistoryWindow.swift
│       ├── Waveform.swift
│       └── AutoPaste.swift
├── Scripts/
│   ├── setup.sh                         # Submodule init + model download
│   ├── build.sh                         # CMake + swift build
│   └── create-dmg.sh                    # Package unsigned DMG
├── CMakeLists.txt                       # C++ core build
├── Package.swift                        # SPM for Swift + bridge
├── Tests/
└── .gitignore
```

## Build Phases

### Phase 1: Scaffold (15 min)
- Rename repo, nuke old files, clean commit
- Create directory structure
- Add whisper.cpp submodule
- Create `setup.sh` (submodule init + model download)
- Create `.gitignore` (models, build artifacts)
- Create `CMakeLists.txt` skeleton
- Create `Package.swift` skeleton
- **Verify:** `bash Scripts/setup.sh` clones whisper.cpp and downloads model

### Phase 2: C++ Core — Audio Recording (1 hr)
- `AudioRecorder.cpp` — FFmpeg + AVFoundation capture
- 35-sec burst architecture with immediate M4A disk writes
- Circular buffer for real-time metering data
- Atomic file operations (write temp → rename)
- `StorageManager.cpp` — JSON metadata, file path management
- **Verify:** C++ test records audio, M4A files appear on disk

### Phase 3: C++ Core — Whisper Transcription (1 hr)
- `WhisperEngine.cpp` — Load base.en model with Metal
- `AudioConverter.cpp` — FFmpeg resamples 44.1kHz M4A → 16kHz mono float32 PCM (whisper.cpp requirement)
- Pipeline: M4A (disk) → FFmpeg decode + resample → float32 PCM buffer → whisper_full()
- Progress callbacks (0-100%)
- **Verify:** Feed M4A file → get transcript text back in < 3 sec

### Phase 4: Obj-C++ Bridge (45 min)
- `WhisperBridge.mm` — transcribe(), loadModel(), progress callback
- `AudioBridge.mm` — startRecording(), stopRecording(), metering callback
- `StorageBridge.mm` — saveSession(), loadHistory(), deleteSession()
- Thread-safe callbacks, memory management
- **Verify:** Swift can call bridge functions, callbacks fire on main thread

### Phase 5: SwiftUI App (1 hr)
- `App.swift` — Entry point, lifecycle
- `AppState.swift` — Global state, hotkey registration (Cmd+Shift+Space)
- `FloatingOverlay.swift` — NSPanel always-on-top, waveform + controls
- `HistoryWindow.swift` — Recording list, playback, retry, delete
- `Waveform.swift` — Core Graphics real-time visualization
- `AutoPaste.swift` — Accessibility API + CGEventPost (Cmd+V simulation)
- **Verify:** App launches, overlay floats, hotkey works, history displays

### Phase 6: Integration + Polish (30 min)
- Connect all layers end-to-end
- Crash recovery: scan for orphaned audio on launch
- Test kill -9 during recording → verify data preserved
- `create-dmg.sh` — unsigned DMG packaging
- **Verify:** Full flow — hotkey → record → transcribe → auto-paste → history

## Info Needed From You

1. **Repo name** — what should I rename it to on GitHub?
2. **Xcode version** — need 15+ for Swift 6 (`xcodebuild -version`)
3. **Accessibility permission** — auto-paste requires granting the app Accessibility access. OK?

## Risks
- **FFmpeg from-source build** adds ~10 min to first `setup.sh` run (one-time cost)
- **CMake + SPM hybrid build** is the hardest part — if it fights us, fallback to pure Xcode project
- **Static linking FFmpeg** — need to get the right configure flags for minimal build
- **whisper.cpp Metal** — need to verify submodule builds with Metal on your machine
- **Accessibility API** — requires explicit user grant in System Settings
