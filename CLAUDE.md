# VoiceRecorder - Agent Instructions

## Project Mission

**Crisis intervention voice recorder for mental health documentation.**

This is NOT a productivity app. This is black box recording infrastructure for people in crisis. Every decision prioritizes:
1. **Never lose data** (reliability)
2. **100% local** (privacy)
3. **Fast enough to not interrupt crisis documentation** (performance)

---

## Core Principles

### NO HARD-CODING
- **Paths**: Check and validate all paths dynamically
- **Configuration**: Use environment variables or config files
- **Dependencies**: Version-pinned in lock files, not in code
- Get an agent to audit all hard-coded values before committing

### USE CURRENT DOCUMENTATION
- If you need documentation, **request it**
- Build a documentation bot if needed
- Make documentation available as skills for other agents
- Don't rely on outdated knowledge
- Check GitHub for latest patterns and issues

### BUILD TO STANDARDS
- **Python**: Use UV package manager, follow PEP standards
- **Swift**: Follow Apple's Swift API Design Guidelines
- **C++**: Follow C++17 best practices
- Use known design patterns from industry leaders

### STREAMING ARCHITECTURE
- **35-second recording bursts** (44kHz sample rate)
- If cut-off or loss occurs, only lose 1 bit of recording
- Everything saved after each burst
- Audio written to disk continuously, not buffered in memory
- Crash recovery: can reconstruct from partial recordings

---

## Technical Requirements

### Audio Recording
- **Sample Rate**: 44,000 Hz (44.1 kHz standard)
- **Burst Length**: 35 seconds maximum per buffer
- **Format**: M4A (AAC compression)
- **Channels**: Mono (1 channel)
- **Streaming**: Write to disk continuously during recording
- **Loss Tolerance**: Maximum 1 bit loss on interruption

**Implementation:**
- FFmpeg with AVFoundation backend
- Circular buffer for real-time metering
- Immediate disk writes (no RAM buffering)
- Atomic file operations for crash safety

### Transcription
- **Engine**: whisper.cpp with M2 Metal acceleration
- **Model**: base.en (142MB, 10-15x real-time)
- **Target Performance**: 30 sec audio → 2-3 sec processing
- **Progressive**: Show progress during transcription
- **Retry**: Any recording can be re-transcribed

### Storage
- **Location**: `~/Library/Application Support/VoiceRecorder/`
- **Format**: JSON metadata + M4A audio + TXT transcripts
- **Atomicity**: All writes use atomic operations
- **Recovery**: Orphaned files detected and processed on launch

### UI
- **Floating Overlay**: NSPanel with `.floating` level
- **Waveform**: Real-time visualization during recording
- **Progress**: Percentage-based during transcription
- **History**: List view with playback/retry/delete
- **Auto-Paste**: Accessibility API to cursor location

---

## Build System

### Dependencies

**Python/UV:**
```bash
# Use UV, not pip
uv venv
uv pip install -r requirements.txt
```

**whisper.cpp (Git Submodule):**
```bash
git submodule add https://github.com/ggml-org/whisper.cpp.git Dependencies/whisper.cpp
cd Dependencies/whisper.cpp
WHISPER_METAL=1 make -j
```

**FFmpeg (Homebrew):**
```bash
brew install ffmpeg
```

### Build Commands

**C++ Core:**
```bash
cmake -B build -DCMAKE_BUILD_TYPE=Release -DWHISPER_METAL=ON
cmake --build build -j
```

**Swift App:**
```bash
swift build -c release
```

**DMG Package:**
```bash
bash Scripts/create-dmg.sh
```

---

## Agent Assignments

### Agent 1: C++ Audio + Whisper Core (3 hours)

**Responsibility**: Bare metal audio processing and transcription

**Files to Create:**
- `Sources/VoiceRecorderCore/WhisperEngine.cpp/.hpp`
- `Sources/VoiceRecorderCore/AudioRecorder.cpp/.hpp`
- `Sources/VoiceRecorderCore/AudioConverter.cpp/.hpp`
- `Sources/VoiceRecorderCore/StorageManager.cpp/.hpp`
- `Sources/VoiceRecorderCore/Types.hpp`

**Requirements:**
- whisper.cpp integration with M2 Metal enabled
- FFmpeg audio recording with 35-sec burst architecture
- FFmpeg PCM conversion (M4A → 16kHz mono float array)
- Progress callbacks for UI (0-100%)
- Atomic file writes, never lose data on crash

**Success Criteria:**
- Record 35-sec bursts to M4A continuously
- Transcribe 30-sec audio in < 3 seconds
- Return progress updates every 100ms
- Handle crash recovery (detect orphaned files)

**Research Needed:**
1. Latest whisper.cpp Metal API (check GitHub)
2. FFmpeg AVFoundation capture examples
3. Atomic file write patterns in C++

---

### Agent 2: Swift UI Layer (1 hour)

**Responsibility**: macOS interface

**Files to Create:**
- `Sources/VoiceRecorder/App.swift`
- `Sources/VoiceRecorder/AppState.swift`
- `Sources/VoiceRecorder/FloatingOverlay.swift`
- `Sources/VoiceRecorder/HistoryWindow.swift`
- `Sources/VoiceRecorder/Waveform.swift`
- `Sources/VoiceRecorder/AutoPaste.swift`

**Requirements:**
- NSPanel floating window (always-on-top)
- Real-time waveform using Core Graphics
- Keyboard shortcut (Cmd+Shift+Space)
- History list with playback controls
- Accessibility API auto-paste

**Success Criteria:**
- Overlay stays above all windows
- Waveform animates smoothly during recording
- Progress bar updates during transcription
- History loads instantly (<200ms for 1000 items)
- Auto-paste works at cursor location

**Research Needed:**
1. Latest NSPanel API for macOS 13+
2. Swift Accessibility API examples
3. CGEventPost for keyboard simulation

---

### Agent 3: Bridge + Storage + Integration (1 hour)

**Responsibility**: Connect Swift UI to C++ core

**Files to Create:**
- `Sources/VoiceRecorderBridge/WhisperBridge.h/.mm`
- `Sources/VoiceRecorderBridge/AudioBridge.h/.mm`
- `Sources/VoiceRecorderBridge/StorageBridge.h/.mm`
- `Sources/VoiceRecorderBridge/VoiceRecorderBridge.h`

**Requirements:**
- Objective-C++ bridges (Swift ↔ C++)
- Memory management (no leaks)
- Thread-safe callbacks
- Error propagation

**Success Criteria:**
- Swift can call C++ functions seamlessly
- No memory leaks (use Instruments to verify)
- Callbacks work from C++ background threads
- Errors propagate to Swift as exceptions

**Research Needed:**
1. Objective-C++ bridging best practices
2. Swift/C++ interop memory management
3. Thread-safe callback patterns

---

### Agent 4: Build + Package (30 min after others)

**Responsibility**: Build system and distribution

**Files to Create:**
- `CMakeLists.txt`
- `Package.swift`
- `Scripts/setup.sh`
- `Scripts/build.sh`
- `Scripts/create-dmg.sh`
- `Scripts/download-model.sh`
- `.gitignore`
- `.gitmodules`
- `README.md`

**Requirements:**
- CMake builds C++ with Metal
- Swift Package Manager integrates everything
- DMG packages app + model (< 200MB)
- Setup script initializes submodules
- No Xcode signing/notarization

**Success Criteria:**
- `bash setup.sh` prepares environment
- `bash build.sh` produces working app
- `bash create-dmg.sh` creates installable DMG
- DMG drag-and-drop installs to Applications

**Research Needed:**
1. CMake Metal framework linking
2. Swift Package Manager + CMake integration
3. hdiutil DMG creation commands

---

## Quality Standards

### Code Review Checklist
- [ ] No hard-coded paths (use environment/config)
- [ ] No hard-coded credentials or secrets
- [ ] All dependencies version-pinned
- [ ] Error handling on all I/O operations
- [ ] Memory leaks checked (Instruments on macOS)
- [ ] Thread safety verified
- [ ] Documentation comments on public APIs
- [ ] Build tested from clean state

### Testing Requirements
- [ ] Record 60 seconds, verify no data loss
- [ ] Kill app during recording, verify crash recovery
- [ ] Fill disk during recording, verify graceful handling
- [ ] Transcribe 30-sec audio in < 3 seconds on M2
- [ ] Auto-paste works in 10+ different apps
- [ ] History loads 1000 recordings in < 200ms

---

## Common Patterns

### Error Handling (C++)
```cpp
// Use std::expected or Result<T, E> pattern
Result<std::string, Error> transcribe(const AudioData& data) {
    if (!data.isValid()) {
        return Error("Invalid audio data");
    }
    // ... processing
    return transcription;
}
```

### Callbacks (C++ → Swift)
```cpp
// C++ side
using ProgressCallback = std::function<void(float)>;

void transcribe(const AudioData& data, ProgressCallback callback) {
    for (int i = 0; i < segments; i++) {
        float progress = (float)i / segments;
        callback(progress);
    }
}
```

```swift
// Swift side
whisperBridge.transcribe(audioPath) { progress in
    DispatchQueue.main.async {
        self.transcriptionProgress = progress
    }
}
```

### Atomic File Writes (C++)
```cpp
// Write to temp, then atomic rename
std::string temp_path = path + ".tmp";
write_file(temp_path, data);
std::filesystem::rename(temp_path, path);  // Atomic on POSIX
```

---

## Performance Targets

| Operation | Target | Maximum |
|-----------|--------|---------|
| Recording start | 50ms | 100ms |
| Transcription (30s) | 2s | 3s |
| Auto-paste delay | 25ms | 50ms |
| History load (1000) | 100ms | 200ms |
| Memory usage | 400MB | 600MB |
| App launch | 1s | 2s |

---

## Security & Privacy

### Data Handling
- **All processing local** (zero network calls)
- **No telemetry** (no analytics, no tracking)
- **No cloud fallback** (even if transcription fails)
- **Encryption at rest** (future: optional AES-256)

### Permissions Required
- Microphone (NSMicrophoneUsageDescription)
- Accessibility (NSAccessibilityUsageDescription)

### Permissions NOT Required
- Network (explicitly disabled)
- Location
- Contacts
- Calendar

---

## Crisis-Specific Considerations

### Why 35-Second Bursts?
- Prevents catastrophic data loss during system crash
- Balances disk I/O with memory efficiency
- Matches typical speech pattern lengths
- Allows partial recovery if interrupted

### Why Immediate Disk Writes?
- Crisis documentation cannot be lost
- RAM is volatile (crash = data loss)
- Disk writes are durable (survives crash)
- Trade: slightly higher disk wear for safety

### Why No Buffering?
- Buffering increases data loss risk
- Crisis users may force-quit during panic
- Immediate writes guarantee data survival
- Performance cost is acceptable (<10ms per write)

---

## Documentation Requirements

### Request Information When Needed
If you need current documentation:
1. Search official sources (Apple Developer, GitHub, Homebrew)
2. Use web search for latest API changes
3. Check GitHub issues for known problems
4. Build documentation bot if needed
5. Make findings available as skills for future agents

### Keep Documentation Current
- Don't rely on outdated training data
- Verify API signatures before using
- Check deprecation notices
- Test on actual M2 hardware

---

## What NOT To Do

❌ Use Swift wrapper libraries (WhisperKit, SwiftWhisper)  
❌ Buffer audio in RAM (write to disk immediately)  
❌ Hard-code paths or configuration  
❌ Use pip (use UV instead)  
❌ Skip error handling  
❌ Assume APIs haven't changed  
❌ Build without testing crash recovery  
❌ Create unsigned builds that require notarization  
❌ Add cloud sync or telemetry  

---

## Final Checklist

Before calling this complete:
- [ ] Records audio in 35-sec bursts
- [ ] Transcribes in < 3 seconds on M2
- [ ] Auto-pastes to cursor location
- [ ] Never loses data (tested with kill -9)
- [ ] History shows all recordings
- [ ] Retry transcription works
- [ ] 100% local (verified with network disabled)
- [ ] DMG installs via drag-and-drop
- [ ] No hard-coded values
- [ ] All paths validated by agent
- [ ] Documentation current
- [ ] Build tested from clean state

---

**This is crisis intervention infrastructure. Build it like lives depend on it. Because they do.**
