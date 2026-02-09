# BPH-002 Recovery Plan — VoiceRecorder

**Date:** 2026-02-09
**Auditor:** Caveman Tier 3 Orchestrator (Claude Opus 4.6)
**Project:** BPH-002 — BrainPhart Voice Recorder (SuperWhisper replacement)
**Location:** `/Users/kjd/01-projects/BPH-002-brainphart-voice-recorder`

---

## Executive Summary

BPH-002 is in **significantly better shape than initially feared**. The codebase is structurally complete — all 32 source files exist as specified, the three-layer architecture (C++ core / Obj-C++ bridge / Swift UI) is properly implemented, and the project **builds successfully** with zero compiler warnings.

A bugfix job (`20260209_000100_001`) ran on 2026-02-09 and resolved the actor isolation warnings that were the root cause of most runtime issues. The code now correctly wraps all bridge callbacks in `Task { @MainActor in }` blocks.

**What works:** Build system, C++ core, Obj-C++ bridge threading, SQLite persistence, project structure, DMG packaging.

**What needs runtime verification:** Floating window visibility, transcription end-to-end, auto-paste, waveform animation, crash recovery. These cannot be verified without launching the app (which requires microphone + accessibility permissions).

**Overall assessment: 70-80% complete. Needs runtime testing and targeted fixes, not a rewrite.**

---

## Documents Reviewed

| Document | Path | Key Content |
|----------|------|-------------|
| CLAUDE.md | `/BPH-002/CLAUDE.md` | Agent instructions, architecture, quality standards (429 lines) |
| PRD v1 | `/BPH-002/PRD/prd-v1.md` | Product requirements, 10 mandatory features, performance targets |
| Shape Up Bet | `/BPH-002/PRD/shapeup-bet-voice-recorder.md` | Problem statement, sketches, scope hammer, user story |
| Technical Proposal v1 | `/BPH-002/Technical/proposal-v1.md` | Architecture, build phases, SQLite schema, file structure |
| Shape Up (Shaping/) | `/BPH-002/Shaping/shapeup-bet-voice-recorder.md` | Duplicate of PRD version |
| dependencies.yaml | `/BPH-002/dependencies.yaml` | whisper.cpp v1.7.3, FFmpeg n7.1, model SHA256 |
| Package.swift | `/BPH-002/Package.swift` | SPM config, 3 targets, 13 frameworks linked |
| CMakeLists.txt | `/BPH-002/CMakeLists.txt` | C++ core build, whisper/FFmpeg/Metal linking |
| Caveman PRD v2.2 | `/EXT-001/PRD/caveman-prd-v2-2-final.md` | Orchestration system design, job lifecycle |
| Caveman Technical Proposal | `/EXT-001/Technical/caveman-technical-proposal.md` | CLI validation, bash 3.2 constraints, rate limit strategy |
| Caveman Job Outputs | `/caveman/outbox/20260209_000100_001.json` | Bugfix job completed, 33 turns, $1.47 cost |
| All 8 Swift source files | `Sources/VoiceRecorder/*.swift` | Full UI layer reviewed |
| All 11 C++ source/header files | `Sources/VoiceRecorderCore/*` | Full core reviewed |
| All 7 bridge files | `Sources/VoiceRecorderBridge/*` | Full bridge reviewed |
| Build scripts | `Scripts/build.sh, setup.sh, create-dmg.sh` | All reviewed |

---

## What Works

### Confirmed Working (Build-Time)
1. **Build succeeds** — `swift build` completes in ~5s with zero compiler warnings
2. **CMake builds** — `libVoiceRecorderCore.a` (104KB static library) compiles cleanly
3. **All dependencies present** — whisper.cpp built with Metal, FFmpeg static libs, model downloaded (148MB)
4. **DMG packaging** — `build/VoiceRecorder.dmg` (148MB) exists and was created
5. **Release binary** — `.build/release/VoiceRecorder` (25MB) exists
6. **Actor isolation fixed** — All bridge callbacks properly wrapped in `Task { @MainActor in }` blocks
7. **Thread safety** — WhisperBridge dispatches progress/completion to main queue; AudioBridge uses same pattern
8. **SQLite persistence** — DatabaseManager uses WAL mode, proper schema with sessions + chunks tables
9. **Config system** — No hardcoded paths; Config.swift resolves model path dynamically
10. **Crash recovery code** — `recoverOrphanedSessions()` in VoiceRecorderApp.swift exists and runs on launch

### Likely Working (Code Reviewed, Needs Runtime Test)
1. **NSPanel floating window** — FloatingPanel properly configured with `.floating` level, `.nonactivatingPanel`, `hidesOnDeactivate = false`, `isMovableByWindowBackground = true`
2. **Global hotkey** — Cmd+Shift+Space registered via both global and local NSEvent monitors
3. **Menu bar item** — NSStatusItem with mic icon and toggle menu
4. **Waveform visualization** — WaveformView uses SwiftUI Canvas, fed by metering timer at 50ms intervals
5. **Auto-paste** — CGEvent-based Cmd+V simulation with accessibility permission check
6. **35-second burst recording** — AudioBridge.onChunkComplete callback wired in AppState
7. **History view** — HistoryView.swift with search, playback controls, retry, delete

---

## What's Broken or Unverified

### CRITICAL — Must Verify by Running App

| # | Issue | Severity | Evidence | Risk |
|---|-------|----------|----------|------|
| C1 | **Transcription end-to-end untested** | HIGH | WhisperBridge.mm code looks correct, but no runtime test confirms audio→PCM→whisper→text pipeline works. Model loading depends on `Config.resolveModelPath()` finding the .bin file at runtime. | If model path resolution fails silently, transcription will never work |
| C2 | **Floating window may not appear** | HIGH | FloatingPanelController code is correct, but `showFloatingOverlay()` is called from `onAppear` of ContentView. If ContentView doesn't appear (e.g., WindowGroup issue), overlay never shows. | The floating overlay is the primary UI |
| C3 | **Audio recording untested** | HIGH | AudioRecorder.cpp uses FFmpeg AVFoundation backend. Requires microphone permission. No way to verify without running. | Core feature |
| C4 | **Model path at runtime** | MEDIUM | `Config.resolveModelPath()` checks 3 candidate paths. When running from `.build/release/`, the binary is NOT in an .app bundle, so `Bundle.main` paths may not resolve. The third candidate tries `Bundle.main.bundleURL.deletingLastPathComponent()/Resources/models/` which may not match the actual project layout. | Transcription won't start if model not found |

### MEDIUM — Known Design Gaps

| # | Issue | Severity | Notes |
|---|-------|----------|-------|
| M1 | **No .app bundle for development runs** | MEDIUM | Running `.build/release/VoiceRecorder` directly means no Info.plist, no entitlements, no bundle resources. Model path resolution, microphone permission prompts, and accessibility permission prompts may behave differently than from a proper .app bundle. |
| M2 | **Duration not tracked correctly** | MEDIUM | `stopRecording()` passes `0` to `completeSession(sessionId, withDuration: 0)`. Should use `recordingElapsedSeconds`. |
| M3 | **No audio playback in history** | LOW | HistoryView likely has playback controls, but playback implementation was not found in the bridge layer. StorageBridge has `getAudioForSession()` but no player wrapper. |
| M4 | **No retry transcription from history UI** | LOW | `retryTranscription(sessionId:)` exists in AppState but binding to HistoryView button may be incomplete. |
| M5 | **Linker warnings (28)** | LOW | macOS version mismatch warnings (deps built for Darwin 26.0, linked to macOS 14.0). Non-fatal, cosmetic only. |

### LOW — Polish Items

| # | Issue | Notes |
|---|-------|-------|
| L1 | **No error UI** | Errors are logged via `os.log` but no user-visible error state in the overlay or history. |
| L2 | **No recording cancellation** | PRD specifies ESC to cancel, not implemented. |
| L3 | **PRD says SQLite, implementation uses SQLite** | Consistent, but no export/backup mechanism. |
| L4 | **No network-disabled verification** | PRD requires zero network calls — not explicitly enforced (no sandbox profile). |

---

## Prioritized Recovery Steps

### Phase 1: Runtime Verification (Effort: 1-2 hours)

The single most important step. Many "bugs" may already be fixed by the bugfix job.

1. **Run the app and observe** — Launch `.build/release/VoiceRecorder` or use `Scripts/build.sh && .build/release/VoiceRecorder`
   - Does the floating overlay appear?
   - Does Cmd+Shift+Space toggle recording?
   - Does the waveform animate?
   - Does transcription produce text?
   - Does auto-paste work?
   - Effort: 30 min

2. **Fix model path resolution if needed** — If transcription fails with "model not loaded":
   - Check Console.app for `[VoiceRecorder]` logs
   - The binary may need to be run from the project root, or `Config.resolveModelPath()` needs a fourth candidate path
   - Effort: 15 min

3. **Test crash recovery** — Force-quit during recording, relaunch, check if orphaned session is recovered
   - Effort: 15 min

4. **Grant permissions** — Microphone + Accessibility in System Settings
   - Effort: 5 min

### Phase 2: Fix Confirmed Bugs (Effort: 1-2 hours)

Only do this after Phase 1 identifies what's actually broken.

5. **Fix duration tracking** — Change `completeSession(sessionId, withDuration: 0)` to pass `recordingElapsedSeconds`
   - File: `AppState.swift:198`
   - Effort: 5 min

6. **Fix model path for non-bundle execution** — Add candidate path relative to executable location or use an environment variable
   - File: `Config.swift:37-54`
   - Effort: 15 min

7. **Fix any floating window issues** — If overlay doesn't appear or doesn't float, check:
   - Is `showFloatingOverlay()` being called?
   - Is the panel level actually `.floating`?
   - Does `hidesOnDeactivate = false` work correctly?
   - Effort: 30 min (if needed)

8. **Fix transcription pipeline** — If whisper doesn't produce output:
   - Check model loading log
   - Check AudioConverter output (is PCM data non-empty?)
   - Check whisper.cpp return value
   - Add debug logging at each stage
   - Effort: 1 hour (if needed)

### Phase 3: Missing Features (Effort: 2-3 hours)

9. **Audio playback in history** — Add AVAudioPlayer wrapper in Swift layer for playing back recorded sessions
   - Effort: 45 min

10. **Recording cancellation (ESC key)** — Add local key monitor for ESC that calls a `cancelRecording()` method
    - Effort: 15 min

11. **Error UI** — Show brief error messages in the floating overlay (e.g., "Model not found", "Mic permission denied")
    - Effort: 30 min

12. **Proper .app bundle** — Update `create-dmg.sh` to create proper .app with Info.plist, entitlements, Resources copied in
    - Effort: 1 hour
    - This is critical for distribution and correct permission prompts

### Phase 4: Polish & Hardening (Effort: 2-3 hours)

13. **Add app sandbox profile** — Enforce zero network access at the OS level
    - Effort: 30 min

14. **Test 1000-recording history performance** — Verify <200ms load target
    - Effort: 30 min

15. **Memory profiling** — Run with Instruments, check for leaks in the C++ bridge
    - Effort: 1 hour

16. **Fill-disk test** — Start recording with low disk space, verify graceful handling
    - Effort: 30 min

---

## Build & Test Instructions

### Prerequisites
```bash
# Already done (verified present):
# - Xcode CLT installed
# - whisper.cpp submodule initialized and built
# - FFmpeg built from source (static libs)
# - Whisper model downloaded (148MB)
```

### Build
```bash
cd /Users/kjd/01-projects/BPH-002-brainphart-voice-recorder

# Full build (C++ core + Swift app)
bash Scripts/build.sh

# Or Swift-only rebuild (if C++ hasn't changed)
swift build -c release
```

### Run
```bash
# From project root (important for model path resolution)
.build/release/VoiceRecorder

# Or from build script output path
.build/arm64-apple-macosx/release/VoiceRecorder
```

### Create DMG
```bash
bash Scripts/create-dmg.sh
# Output: build/VoiceRecorder.dmg (148MB)
```

### Verify Build Health
```bash
# Should complete with zero compiler warnings (linker warnings are OK)
swift build 2>&1 | grep -c "warning:" | grep -v "ld:"
# Expected: 0

# Check binary exists and is reasonable size
ls -lh .build/release/VoiceRecorder
# Expected: ~25MB
```

---

## Risk Assessment

| Risk | Probability | Impact | Mitigation |
|------|-------------|--------|------------|
| Model path doesn't resolve at runtime | MEDIUM | HIGH (no transcription) | Add fallback paths, test from .app bundle and bare binary |
| FFmpeg AVFoundation capture fails | LOW | HIGH (no recording) | Well-tested API, but needs mic permission granted first |
| whisper.cpp Metal acceleration fails | LOW | MEDIUM (slow, not broken) | Falls back to CPU; test with `GGML_METAL_LOG_LEVEL=3` env var |
| Actor isolation still causes runtime crashes | LOW | HIGH | Code review shows correct `@MainActor` patterns throughout |
| Memory leak in C++ bridge | MEDIUM | MEDIUM (gradual degradation) | Need Instruments profiling in Phase 4 |
| .app bundle packaging incomplete | HIGH | MEDIUM (works in dev, breaks in distribution) | create-dmg.sh exists but Info.plist and entitlements need verification |
| Accessibility permission not grantable without .app | MEDIUM | HIGH (no auto-paste) | May need proper code-signed .app bundle for System Settings to show the entry |
| SQLite corruption on force-quit | LOW | HIGH (data loss) | WAL mode + atomic transactions should prevent this; test in Phase 1 |

### Overall Risk Rating: **MEDIUM**

The code is structurally sound and builds cleanly. The primary risk is runtime integration — components that work individually may not connect properly end-to-end. Phase 1 (runtime verification) will immediately reveal how much additional work is needed. The worst case is 6-8 hours of additional work; the best case is 1-2 hours of targeted fixes.

---

## Architecture Diagram (As-Built)

```
┌──────────────────────────────────────────────┐
│  Swift UI Layer                               │
│  VoiceRecorderApp.swift  (entry + bootstrap) │
│  AppState.swift          (state machine)     │
│  FloatingOverlay.swift   (NSPanel overlay)   │
│  ContentView.swift       (main window)       │
│  HistoryView.swift       (session browser)   │
│  WaveformView.swift      (Canvas waveform)   │
│  AutoPaste.swift         (CGEvent paste)     │
│  Config.swift            (centralized config)│
└──────────────┬───────────────────────────────┘
               │ SwiftUI imports ObjC headers
┌──────────────▼───────────────────────────────┐
│  Objective-C++ Bridge Layer                   │
│  AudioBridge.mm     (recording lifecycle)    │
│  WhisperBridge.mm   (transcription pipeline) │
│  StorageBridge.mm   (SQLite CRUD)            │
│  VoiceRecorderBridge.h (umbrella header)     │
│  All callbacks dispatch to main queue        │
└──────────────┬───────────────────────────────┘
               │ C++ method calls
┌──────────────▼───────────────────────────────┐
│  C++ Core (libVoiceRecorderCore.a, 104KB)    │
│  AudioRecorder.cpp   (FFmpeg AVFoundation)   │
│  WhisperEngine.cpp   (whisper.cpp wrapper)   │
│  AudioConverter.cpp  (M4A→16kHz PCM)         │
│  DatabaseManager.cpp (SQLite WAL mode)       │
│  StorageManager.cpp  (high-level orchestrator)│
│  Types.hpp           (shared enums/structs)  │
└──────────────┬───────────────────────────────┘
               │ Links against
┌──────────────▼───────────────────────────────┐
│  Dependencies                                 │
│  whisper.cpp  (Metal GPU acceleration)       │
│  FFmpeg       (static libs, n7.1)            │
│  SQLite3      (system framework)             │
│  Metal + Accelerate + AVFoundation           │
└──────────────────────────────────────────────┘
```

---

## Git History (4 Commits)

```
495b36a Implement core: whisper.cpp transcription, FFmpeg recording, bridge fixes
97f4f03 Add whisper.cpp submodule for Metal-accelerated transcription
dd7e16c MVP scaffold: C++ core, Obj-C++ bridge, SwiftUI app
f669b08 Fresh start: VoiceRecorder macOS native
```

Plus one Caveman-dispatched bugfix job completed (session `aad8a62d`, 33 turns, 276s).

---

## Recommendation

**Do Phase 1 immediately.** Launch the app, observe behavior, and create a concrete bug list. The code quality is high and the architecture is sound — the remaining work is integration testing and targeted fixes, not architectural changes.

If Phase 1 reveals the app is mostly working, the total remaining effort is **2-4 hours**. If transcription or recording are fundamentally broken, budget **6-8 hours** for debugging the C++ core and FFmpeg pipeline.

**This project is recoverable. It is not a rewrite candidate.**
