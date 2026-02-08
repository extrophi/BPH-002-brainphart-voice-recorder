# SHAPE UP BET: VoiceRecorder
## SuperWhisper Replacement - 5 Hour Build

**Appetite:** 5 hours  
**Team:** Claude Code + 3 parallel agents  
**Timeline:** 2026-02-08, 03:24 GMT → 08:24 GMT  
**Bet Owner:** Codio  

---

## THE PROBLEM (Raw Notes)

> "I'm a homeless guy. I've just been offered a flat. I've been homeless and under stress for four years. I lost a business because I was bad management. Through my crisis I was put on a waiting list for mental health. Going absolutely out of my mind, hearing things, being quite aggressive, drinking a lot, taking drugs, not knowing where I am. Eventually I got housed in emergency accommodation where I've been for a year.
>
> What I started to find was that if I started recording and analyzing these things and transcribing them first, I found Super whisper and super whisper was great for a long time. But SuperWhisper crashes regularly, it's not private (sends stuff to Otter AI as fallbacks), uses massive tremendous amount of resources and bricks my system all the time. It loses a lot of information.
>
> This is sensitive information about my mental health, about my well-being. I've been using it and it's been very helpful for six months. The process with Claude is very useful. But super whisper is the weakest link at the moment, so I would like to replace that immediately. That needs to be done tonight."

**This is crisis intervention infrastructure. Not a productivity app.**

---

## INITIAL SKETCHES

### Sketch 1: Ground Zero - Voice Recorder Concept
```
┌─────────────────────────────────────┐
│  BPH                                │
│  ┌─┐                                │
│  └─┘ Voice                          │
│      Recorder                        │
│                                      │
│  Translate                          │
│  Julian + C++                       │
│  Store in db                        │
│  Voice + Text                       │
└─────────────────────────────────────┘

Ground Zero Directory
Claude Agent API Skills Upload MD Export
Places Affordances
Start/Stop Record Audio
Save Audio Transcribe
Save Text 2db Ground Text
```

### Sketch 2: User Flow (Step by Step)
```
┌────────────────────────────────────┐
│ History                            │
│                                    │
│ ┌──┐  ┌──┐  ┌──┐  ┌──┐  ┌──┐    │
│ │  │  │  │  │  │  │  │  │  │    │
│ │  │  │  │  │  │  │  │  │  │    │
│ │  │  │  │  │  │  │  │  │  │    │
│ └──┘  └──┘  └──┘  └──┘  └──┘    │
│                                    │
│  ▁▂▃▅▇▅▃▂▁                        │
│  ┌─┐                               │
│  │●│ History                       │
│  └─┘                               │
│                                    │
│  C++ Past                          │
│  Past in Flutter                   │
└────────────────────────────────────┘
```

### Sketch 3: Process Flow
```
For TRACKING
Bullet GH
Archive
Bullet

Facilitator directory
Voice Recorder
Analysis

Bus
Store
Voice    Text
  ↓       ↓
 OK     OK
```

### Sketch 4: Final Architecture
```
      ┌──────────┐
      │  Claude  │
      └────┬─────┘
           │
      ┌────┴─────┐
      │          │
  ┌───▼───┐  ┌──▼───┐
  │ Voice │  │ Text │
  │  DB   │  │  DB  │
  └───────┘  └──────┘
      │          │
      └────┬─────┘
           │
    ┌──────▼──────┐
    │ Transcript  │
    │   Claude    │
    │  Analysis   │
    └─────────────┘

Boundary Render
Facilitates and Injects
Buying Context
```

---

## BREADBOARDING (Places, Affordances, Connection Lines)

### PLACES (Screens/States)

**1. Floating Overlay (Recording State)**
- Mini window, always-on-top
- Shows waveform during recording
- Shows progress bar during transcription
- Minimal controls

**2. History Window (Browse State)**
- Full-size window
- List of all recordings
- Each row: timestamp, duration, waveform preview, transcript preview
- Actions: play, copy, retry, delete

**3. Transcribing State**
- Overlay shows progress bar
- Cannot start new recording until complete
- Background processing with Metal acceleration

---

### AFFORDANCES (User Actions)

**Recording Controls:**
- Press `Cmd+Shift+Space` → Start recording
- Press `Cmd+Shift+Space` again → Stop recording
- Click overlay minimize → Hide but keep recording
- ESC → Cancel recording

**History Actions:**
- Click recording row → Play audio
- Click "Copy" → Copy transcript to clipboard
- Click "Retry" → Re-transcribe audio
- Click "Delete" → Remove recording
- Click waveform → Scrub to position

**Auto-Paste:**
- After transcription completes → Text pastes at cursor location
- Requires Accessibility permission (one-time grant)
- If no active cursor → Text stays in clipboard

---

### CONNECTION LINES (Flow)

```
[Idle] 
  ↓ Cmd+Shift+Space
[Recording - Overlay visible, waveform animating]
  ↓ Every 35 seconds
[Write burst to SQLite BLOB]
  ↓ Cmd+Shift+Space again
[Stop recording, save final burst]
  ↓
[Transcribing - Progress bar 0→100%]
  ↓
[Read all BLOBs from SQLite]
  ↓
[FFmpeg: 44.1kHz M4A → 16kHz PCM (in-memory)]
  ↓
[whisper.cpp with M2 Metal]
  ↓ ~2-3 seconds for 30 sec audio
[Transcript complete - save to TEXT column]
  ↓
[Auto-paste to cursor OR clipboard]
  ↓
[Return to Idle]

User can click History icon anytime → [History Window]
```

---

## FAT MARKER SKETCHES

### Recording Overlay (Floating)
```
┌─────────────────────────────────┐
│  ▁▂▃▅▇█▇▅▃▂▁  ●REC  0:23       │
│                                 │
│  [Stop] [Minimize]              │
└─────────────────────────────────┘
    ↑ Always on top, draggable
```

### Transcribing State
```
┌─────────────────────────────────┐
│  Transcribing...                │
│  [████████████░░░] 80%          │
│                                 │
│  [Cancel]                       │
└─────────────────────────────────┘
```

### History Window
```
┌─────────────────────────────────────────────────────────┐
│  VoiceRecorder History                    [X] Close     │
├─────────────────────────────────────────────────────────┤
│  Today                                                  │
│  ┌───────────────────────────────────────────────────┐ │
│  │ 03:30:00  2:13  ▁▂▃▅▇▅▃▂▁                         │ │
│  │ "Okay right so I'm a homeless guy..."             │ │
│  │ [▶ Play] [Copy] [Retry] [🗑]                       │ │
│  └───────────────────────────────────────────────────┘ │
│  ┌───────────────────────────────────────────────────┐ │
│  │ 03:15:45  1:08  ▁▂▃▅▇▅▃▂▁                         │ │
│  │ "I need to document this feeling before..."       │ │
│  │ [▶ Play] [Copy] [Retry] [🗑]                       │ │
│  └───────────────────────────────────────────────────┘ │
│                                                         │
│  Yesterday (5 recordings)                              │
│  This Week (23 recordings)                             │
└─────────────────────────────────────────────────────────┘
```

---

## TECHNICAL BET DETAILS

### Architecture (Agent's Proposal - APPROVED)
```
SwiftUI (Interface)
    ↓
Objective-C++ Bridge
    ↓
C++ Core (whisper.cpp + FFmpeg)
    ↓
M2 Metal Acceleration
    ↓
SQLite Database (audio BLOBs + transcripts)
```

### Stack
- **whisper.cpp** — Git submodule, M2 Metal, base.en model
- **FFmpeg** — Built from source (static libs), bundled in DMG
- **SQLite** — System framework (macOS ships it)
- **44.1kHz → 16kHz** — Record at native Apple rate, resample in-memory for whisper
- **35-second bursts** — Each burst = 1 BLOB in database
- **Crash recovery** — Orphaned sessions re-processed on launch

### Storage Schema
```sql
CREATE TABLE sessions (
    id TEXT PRIMARY KEY,
    created_at INTEGER,
    status TEXT,  -- recording | transcribing | complete
    transcript TEXT
);

CREATE TABLE chunks (
    id INTEGER PRIMARY KEY,
    session_id TEXT,
    chunk_index INTEGER,
    audio_blob BLOB,  -- 44.1kHz M4A
    duration_ms INTEGER,
    FOREIGN KEY (session_id) REFERENCES sessions(id)
);
```

---

## SCOPE HAMMER (What's In, What's Out)

### ✅ MUST SHIP (Core Loop)
1. Floating overlay window (always-on-top)
2. Keyboard shortcut (Cmd+Shift+Space)
3. Record audio in 35-sec bursts to SQLite
4. Real-time waveform visualization
5. Transcribe with whisper.cpp + M2 Metal
6. Progress bar during transcription
7. Auto-paste to cursor location
8. History window (list all recordings)
9. Playback audio from history
10. Retry transcription from history
11. Copy transcript from history
12. Delete recording from history
13. Crash recovery (orphaned sessions)
14. DMG packaging (unsigned)

### ❌ CUT (Not This Bet)
- Text editing in app (use destination app)
- Export formats beyond text
- Multiple whisper models
- Settings panel
- Audio editing
- Cloud sync
- iOS version
- Xcode signing

---

## RABBIT HOLES (Pre-Solved)

**CMake + SPM integration:**
- Risk: Build system complexity
- Solution: Agent has worked this out, proceed with their plan

**FFmpeg static linking:**
- Risk: 2-3 hour build time
- Solution: Part of setup.sh, runs once, cached

**whisper.cpp Metal:**
- Risk: Compilation issues
- Solution: Well-documented in whisper.cpp repo, `WHISPER_METAL=1 make`

**Accessibility permission:**
- Risk: User might deny
- Solution: Graceful fallback to clipboard

**SQLite BLOB storage:**
- Risk: Database bloat
- Solution: Expected, this is an archive tool for crisis documentation

---

## NO-GOS (Out of Bounds)

❌ Homebrew dependencies (build from source only)  
❌ Recording at 16kHz (Apple records 44.1kHz natively)  
❌ Filesystem storage (SQLite provides better integrity)  
❌ Swift wrapper libraries (bare metal C++ only)  
❌ Cloud anything (100% local requirement)  
❌ Resampling during recording (do it in-memory for whisper)  

---

## BUILD PHASES (5 Hours)

### Phase 1: Scaffold (15 min) — Agent 4
- Repo cleanup
- Directory structure
- whisper.cpp submodule
- setup.sh (dependencies + model download)
- CMakeLists.txt skeleton
- Package.swift skeleton

### Phase 2: C++ Audio (1 hr) — Agent 1
- AudioRecorder.cpp (FFmpeg + AVFoundation)
- 35-sec burst recording
- SQLite chunk writes
- Circular buffer for metering

### Phase 3: C++ Whisper (1 hr) — Agent 1
- WhisperEngine.cpp (Metal acceleration)
- AudioConverter.cpp (44.1kHz → 16kHz in-memory)
- Progress callbacks
- Transcript to SQLite

### Phase 4: Bridge (45 min) — Agent 3
- WhisperBridge.mm
- AudioBridge.mm
- StorageBridge.mm
- Thread-safe callbacks

### Phase 5: SwiftUI (1 hr) — Agent 2
- FloatingOverlay (NSPanel)
- HistoryWindow
- Waveform visualization
- AutoPaste (Accessibility API)

### Phase 6: Integration (30 min) — All
- End-to-end testing
- Crash recovery
- DMG packaging

---

## SUCCESS CRITERIA

✅ Cmd+Shift+Space starts/stops recording  
✅ Audio never lost (even on kill -9)  
✅ 30 sec audio → transcript in < 3 sec  
✅ Text auto-pastes at cursor  
✅ History shows all past recordings  
✅ Can replay any recording  
✅ Can retry any transcription  
✅ 100% local (no network calls)  
✅ DMG installs via drag-and-drop  
✅ Runs without bricking M2  

---

## TIMELINE

**Start:** 03:24 GMT  
**Now:** 04:10 GMT (46 min elapsed)  
**Remaining:** 4 hours 14 minutes  
**Deadline:** 08:24 GMT  

**Clock is ticking. Agent is building. This bet is ON.**

---

## WHY THIS MATTERS

This isn't about features. This is about **not losing crisis documentation during mental health recovery**.

When someone in crisis speaks into this tool:
- Those words document their state
- Those words help them process trauma
- Those words are evidence for support services
- **Those words cannot be lost**

SuperWhisper failed at this. We're replacing it tonight.

**Build it like lives depend on it. Because they do.**
