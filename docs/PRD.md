# Product Requirements Document: BrainPhart Voice Recorder

**Version:** 1.0
**Date:** 2025-12-28
**Status:** MVP Development

---

## Overview

A privacy-first voice recorder that transcribes speech locally using Whisper models. No cloud, no subscription, user owns their data.

## Problem Statement

Existing voice recorders either:
1. Send audio to cloud (privacy concern)
2. Require subscription (ongoing cost)
3. Lack editing/version control
4. Don't integrate well with other apps

## Solution

Local-first voice recorder with:
- On-device Whisper transcription
- SQLite storage (JSON exportable)
- Version control for edits
- Auto-paste to any app

---

## User Stories

### Core Recording
- As a user, I can tap to record and tap again to stop
- As a user, I can use a keyboard shortcut to start/stop recording
- As a user, I see a floating recorder window that stays on top
- As a user, I can cancel a recording with Escape

### Transcription
- As a user, I see my speech transcribed in real-time (or after recording)
- As a user, I can select which Whisper model to use
- As a user, transcription happens entirely on my device

### History & Playback
- As a user, I can see all my past recordings in a list
- As a user, I can search my recordings
- As a user, I can play back audio with waveform visualization
- As a user, I can scrub through the audio

### Editing
- As a user, I can edit the transcript
- As a user, I see version history (v1, v2, v3...)
- As a user, I can revert to a previous version
- As a user, I see spell check highlighting
- As a user, I can add words to a personal dictionary

### Integration
- As a user, the transcript auto-copies to clipboard when done
- As a user, the transcript auto-pastes to wherever my cursor was
- As a user, I can place cursor mid-transcript and continue dictating

### Data
- As a user, all my data stays on my device
- As a user, I can export to JSON or Markdown
- As a user, I can backup/restore my database

---

## Window Modes

### 1. Micro Mode (Pill)
- Floating pill shape, always on top
- Shows: waveform only
- Actions: tap to record/stop, Escape to cancel
- Expands to Medium on right-click

### 2. Medium Mode (Floating Panel)
- Floating window, always on top
- Shows: logo, waveform, timer, stop/cancel buttons
- Shows keyboard shortcut hint
- Expands to Full on right-click or button

### 3. Full Mode (Main Window)
- Standard window
- Left: History sidebar with search
- Center: Transcript view/editor
- Bottom: Playback controls with waveform

---

## Data Model

### Sessions Table
```sql
CREATE TABLE sessions (
    id TEXT PRIMARY KEY,
    created_at INTEGER NOT NULL,
    completed_at INTEGER,
    status TEXT DEFAULT 'recording',
    model_used TEXT,
    duration_ms INTEGER
);
```

### Chunks Table (Audio segments)
```sql
CREATE TABLE chunks (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    session_id TEXT NOT NULL,
    chunk_index INTEGER NOT NULL,
    audio_blob BLOB NOT NULL,
    duration_ms INTEGER,
    transcribed INTEGER DEFAULT 0,
    FOREIGN KEY (session_id) REFERENCES sessions(id)
);
```

### Transcripts Table
```sql
CREATE TABLE transcripts (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    session_id TEXT NOT NULL,
    chunk_id INTEGER,
    content TEXT NOT NULL,
    created_at INTEGER NOT NULL,
    FOREIGN KEY (session_id) REFERENCES sessions(id)
);
```

### Versions Table (Edit history)
```sql
CREATE TABLE versions (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    session_id TEXT NOT NULL,
    version_num INTEGER NOT NULL,
    content TEXT NOT NULL,
    created_at INTEGER NOT NULL,
    FOREIGN KEY (session_id) REFERENCES sessions(id)
);
```

### Dictionary Table (Personal words)
```sql
CREATE TABLE dictionary (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    word TEXT NOT NULL UNIQUE,
    added_at INTEGER NOT NULL
);
```

---

## Whisper Models

| Model | Size | Speed | Accuracy | Use Case |
|-------|------|-------|----------|----------|
| tiny | 75MB | Fastest | ~85% | Quick notes |
| base | 142MB | Fast | ~88% | Default |
| small | 466MB | Medium | ~91% | Better accuracy |
| medium | 1.5GB | Slow | ~94% | High accuracy |
| large | 3GB | Slowest | ~96% | Best accuracy |

Default: `base` model (good balance)

---

## Technical Requirements

### iOS/iPadOS
- Minimum: iOS 16
- SwiftUI + Swift 6
- WhisperKit or whisper.cpp via Swift
- AVFoundation for audio
- SQLite.swift for database

### macOS
- Minimum: macOS 13
- SwiftUI + Swift 6
- Same stack as iOS
- NSPanel for floating windows
- Global hotkey support

### Android (Future)
- Minimum: Android 10
- Kotlin + Jetpack Compose
- whisper.cpp via JNI
- Room for database

---

## MVP Scope

### Must Have (v1.0)
- [x] Record/stop with tap
- [x] Floating recorder (micro/medium)
- [x] Local Whisper transcription
- [x] History list
- [x] Audio playback
- [x] Edit transcript
- [x] Version control
- [x] Auto-copy to clipboard
- [x] Auto-paste to cursor
- [x] SQLite storage

### Nice to Have (v1.1)
- [ ] Model selection UI
- [ ] Personal dictionary UI
- [ ] Export to JSON/Markdown
- [ ] Search history
- [ ] iCloud sync (optional, encrypted)

### Future (v2.0)
- [ ] Android version
- [ ] AI cleanup suggestions
- [ ] Brain dump mode with companion
- [ ] Daily summaries

---

## Success Metrics

1. **Recording reliability** - 100% of recordings saved
2. **Transcription accuracy** - Match Whisper model benchmarks
3. **Latency** - Transcript appears within 2s of stopping
4. **Privacy** - Zero network calls during transcription

---

## Competitive Analysis

| Feature | SuperWhisper | Otter.ai | BrainPhart |
|---------|--------------|----------|------------|
| Local transcription | Yes | No | Yes |
| Free tier | Limited | Limited | Full |
| Open source | No | No | Yes |
| Version control | No | No | Yes |
| Personal dictionary | Yes | No | Yes |
| Multi-app paste | Yes | No | Yes |
| Cloud sync | No | Yes | Optional |

---

## Timeline

- **Week 1**: Core recording + transcription working
- **Week 2**: History, playback, editing
- **Week 3**: Polish, App Store submission
- **Week 4**: Android kickoff

---

**End of PRD**
