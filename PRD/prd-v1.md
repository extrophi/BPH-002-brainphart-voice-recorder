# VoiceRecorder - Product Requirements Document v1

**Project:** SuperWhisper Replacement - Crisis Intervention Voice Recorder  
**Timeline:** 5 hours (parallel agent build)  
**Platform:** macOS M2 native  
**Date:** 2026-02-08  

---

## Problem Statement

SuperWhisper is failing as crisis intervention infrastructure:
- **Loses sensitive mental health data** (crashes during recording/transcription)
- **Privacy violations** (sends data to Otter AI as fallback)
- **System instability** (bricks M2 with excessive resource usage)
- **Unreliable** (requires constant restarts, loses transcriptions)

This is **unacceptable** for someone using voice recording to manage PTSD recovery and document mental health progress.

---

## Solution

Native macOS app using **whisper.cpp + FFmpeg** for bare metal M2 Metal performance. 100% local, zero cloud, never loses data.

---

## Architecture

```
Swift UI (Interface) 
    ↓
Objective-C++ Bridge
    ↓
C++ Core (whisper.cpp + FFmpeg)
    ↓
M2 Metal Acceleration
```

**No Swift wrappers. No compromise. Bare metal only.**

---

## Technical Stack

### Core Processing (C++)
- **whisper.cpp**: M2 Metal acceleration, base.en model (142MB)
- **FFmpeg**: Audio recording (AVFoundation), conversion to PCM
- **Storage**: Direct filesystem I/O, JSON metadata

### UI Layer (Swift)
- **FloatingOverlay**: NSPanel always-on-top recording window
- **HistoryWindow**: Full-size history browser
- **AutoPaste**: Accessibility API for cursor-location paste

### Bridge (Objective-C++)
- WhisperBridge: Swift ↔ C++ transcription
- AudioBridge: Swift ↔ C++ recording
- StorageBridge: Swift ↔ C++ file I/O

---

## Mandatory Features (All Ship in 5 Hours)

### 1. Floating Overlay
- Always-on-top window (NSPanel with .floating level)
- Real-time waveform visualization during recording
- Progress bar during transcription
- Minimal UI: just waveform + controls

### 2. Keyboard Shortcut
- **Cmd+Shift+Space**: Start/stop recording
- Global hotkey works in any app
- Single keypress toggles record/stop

### 3. Audio Recording
- FFmpeg captures from AVFoundation device
- Saves to M4A format immediately on stop
- Real-time metering for waveform display
- 16kHz mono optimized for whisper.cpp

### 4. Transcription
- whisper.cpp base.en model with M2 Metal
- Target: 30 sec audio → 2-3 sec transcription (10-15x real-time)
- Progress callbacks for UI updates
- Never block UI during processing

### 5. Auto-Paste to Cursor
- Transcribed text pastes at cursor location (not clipboard)
- Uses Accessibility API + CGEventPost (Cmd+V simulation)
- Requires one-time Accessibility permission grant
- Primary path, not fallback

### 6. History Tab
- Every recording saved with:
  - Audio file (M4A)
  - Transcript (TXT)
  - Timestamp
  - Duration
  - Waveform data
- Click any recording to:
  - Play audio
  - Copy transcript
  - Retry transcription
  - Delete recording

### 7. Never Lose Data
- Audio file created and written immediately on recording start
- Transcript saved immediately on completion
- Crash recovery: orphaned audio files transcribed on next launch
- Storage: `~/Library/Application Support/VoiceRecorder/`

### 8. 100% Local
- Zero cloud, zero network calls
- All processing on M2 Metal
- No telemetry, no analytics, no tracking
- whisper.cpp model bundled in app

### 9. Retry Transcription
- Any recording in history can be re-transcribed
- Useful if first attempt failed or was interrupted
- Uses same whisper.cpp engine

### 10. DMG Package
- Unsigned (no Apple notarization bullshit)
- Drag-and-drop install to Applications
- Bundles whisper.cpp model (142MB)
- Includes FFmpeg libraries

---

## Performance Requirements

| Metric | Target |
|--------|--------|
| Recording start | < 100ms |
| Transcription (30 sec audio) | 2-3 seconds |
| Auto-paste after transcription | < 50ms |
| History load (1000 recordings) | < 200ms |
| Memory during transcription | < 600MB |
| App launch | < 2 seconds |

---

## File Structure

```
VoiceRecorder/
├── Sources/
│   ├── VoiceRecorder/           # Swift UI
│   ├── VoiceRecorderCore/       # C++ core
│   └── VoiceRecorderBridge/     # Obj-C++ bridge
├── Dependencies/
│   └── whisper.cpp/             # Git submodule
├── Resources/
│   └── models/
│       └── ggml-base.en.bin     # 142MB
├── Scripts/
│   ├── setup.sh
│   ├── build.sh
│   └── create-dmg.sh
└── Tests/
```

---

## Data Storage

**Location:** `~/Library/Application Support/VoiceRecorder/`

**Structure:**
```
VoiceRecorder/
├── recordings.json              # Metadata index
├── audio/
│   ├── 2026-02-08-03-30-00.m4a
│   ├── 2026-02-08-03-35-15.m4a
└── transcripts/
    ├── 2026-02-08-03-30-00.txt
    ├── 2026-02-08-03-35-15.txt
```

**recordings.json format:**
```json
{
  "recordings": [
    {
      "id": "2026-02-08-03-30-00",
      "audioFile": "audio/2026-02-08-03-30-00.m4a",
      "transcriptFile": "transcripts/2026-02-08-03-30-00.txt",
      "timestamp": "2026-02-08T03:30:00Z",
      "duration": 35.5,
      "transcript": "full text here..."
    }
  ]
}
```

---

## Dependencies

### whisper.cpp (Git Submodule)
- Repo: https://github.com/ggml-org/whisper.cpp
- Version: Latest with M2 Metal support
- Model: base.en (142MB, 10-15x real-time)
- Build flags: `WHISPER_METAL=1`

### FFmpeg (Homebrew or Static)
- Install: `brew install ffmpeg`
- Required libs:
  - libavformat
  - libavcodec
  - libavutil
  - libavdevice
  - libswresample

### System Frameworks
- Metal.framework (M2 acceleration)
- MetalKit.framework
- Accelerate.framework
- AVFoundation.framework
- Accessibility (for auto-paste)

---

## Build System

### CMake (C++ Core)
```cmake
cmake_minimum_required(VERSION 3.20)
set(WHISPER_METAL ON)
add_subdirectory(Dependencies/whisper.cpp)
find_package(FFMPEG REQUIRED)
target_link_libraries(VoiceRecorderCore whisper ${FFMPEG_LIBRARIES})
```

### Swift Package Manager (UI + Bridge)
```swift
.executableTarget(
    name: "VoiceRecorder",
    dependencies: ["VoiceRecorderBridge"]
)
```

---

## Parallel Agent Assignments (5 Hours)

### Agent 1: C++ Audio + Whisper (3 hours)
**Files:**
- `WhisperEngine.cpp/.hpp`
- `AudioRecorder.cpp/.hpp`
- `AudioConverter.cpp/.hpp`

**Tasks:**
- whisper.cpp integration with M2 Metal
- FFmpeg audio recording pipeline
- FFmpeg M4A → PCM conversion
- Progress callbacks for UI

**Done when:**
- Can record audio to M4A
- Can transcribe M4A to text
- Returns progress percentages
- Achieves 10-15x real-time performance

---

### Agent 2: Swift UI (1 hour)
**Files:**
- `App.swift`
- `AppState.swift`
- `FloatingOverlay.swift`
- `HistoryWindow.swift`
- `Waveform.swift`

**Tasks:**
- Floating overlay window (NSPanel)
- Waveform visualization (Core Graphics)
- History list view
- Keyboard shortcut registration

**Done when:**
- Overlay stays on top of all windows
- Waveform animates during recording
- Progress bar shows during transcription
- History displays all recordings

---

### Agent 3: Bridge + Storage + Auto-Paste (1 hour)
**Files:**
- `WhisperBridge.h/.mm`
- `AudioBridge.h/.mm`
- `StorageBridge.h/.mm`
- `StorageManager.cpp/.hpp`
- `AutoPaste.swift`

**Tasks:**
- Objective-C++ bridges (Swift ↔ C++)
- File I/O and JSON management
- Accessibility API auto-paste

**Done when:**
- Swift can call C++ functions
- Files save/load reliably
- Auto-paste works at cursor location
- Never loses data on crash

---

### Agent 4: Build + Package (30 min after others finish)
**Files:**
- `CMakeLists.txt`
- `Package.swift`
- `Scripts/setup.sh`
- `Scripts/build.sh`
- `Scripts/create-dmg.sh`

**Tasks:**
- CMake configuration
- Build scripts
- DMG packaging
- Bundle model + FFmpeg

**Done when:**
- `bash build.sh` produces working app
- `bash create-dmg.sh` produces installable DMG
- DMG is < 200MB total

---

## No-Gos (Explicitly Cut)

❌ Cloud sync  
❌ Multiple whisper models  
❌ Audio editing features  
❌ Export to formats other than text  
❌ Settings panel (hardcode everything)  
❌ iOS/Windows versions  
❌ Xcode signing/notarization  
❌ Swift wrapper libraries (WhisperKit, SwiftWhisper, etc.)  

---

## Success Criteria

✅ Records audio with keyboard shortcut  
✅ Transcribes 30 sec audio in < 3 seconds  
✅ Auto-pastes text at cursor location  
✅ Never loses data (even on crash)  
✅ History shows all past recordings  
✅ Can retry any transcription  
✅ 100% local (zero network calls)  
✅ Installs via drag-and-drop DMG  
✅ Runs on M2 without bricking system  

---

## Timeline

**Start:** 03:24 GMT, 2026-02-08  
**Deadline:** 08:24 GMT, 2026-02-08  
**Duration:** 5 hours  

**Agent deployment:**
- Agents 1, 2, 3 work in parallel (first 3 hours)
- Agent 4 packages after others complete (final 30 min)

---

## Critical Notes

**This is NOT a productivity app.**  
**This is crisis intervention infrastructure.**  

Every design decision prioritizes:
1. **Reliability** (never lose data)
2. **Privacy** (100% local)
3. **Performance** (fast enough not to interrupt crisis documentation)

Speed matters because someone in crisis cannot wait 30 seconds for transcription.

Privacy matters because this documents sensitive mental health information.

Reliability matters because losing a recording means losing crucial crisis documentation.

**Build it right. Build it fast. Build it tonight.**
