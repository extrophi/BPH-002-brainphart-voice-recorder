# BrainPhart Voice Recorder

Privacy-first voice recorder with on-device WhisperKit transcription and system-wide keyboard extension.

## Current Status: iOS MVP Complete (2025-12-29)

### Working Features

**Keyboard Extension (Transcript)**
- Voice-to-text anywhere - Messages, Safari, Notes, any app
- On-device WhisperKit transcription (tiny.en model)
- Auto-paste into text field
- Edit button opens main app with session ID
- Audio session properly released after recording

**Main App**
- One-tap recording with waveform visualization
- Live transcription progress display
- Transcript result shown immediately with Copy/View buttons
- History tab with all recordings
- Keyboard/app source indicator (keyboard icon)
- Auto-refresh when app foregrounds
- Audio playback in History

**Database Architecture**
- Single source of truth - SQLite in App Groups container
- Shared between app and keyboard extension
- Audio stored as BLOB (no filesystem dependencies)
- Source tracking: 'app' vs 'keyboard'

## Technical Stack

- **SwiftUI** - iOS 17+
- **WhisperKit** - On-device speech recognition
- **SQLite3** - Direct C API
- **App Groups** - `group.com.brainphart.voicerecorder`
- **Live Activities** - Lock screen recording indicator

## Project Structure

```
BPH-002-brainphart-voice-recorder/
├── VoiceRecorder/
│   ├── VoiceRecorderApp.swift    # Entry, URL handling, AppState
│   ├── ContentView.swift         # Tabs, RecordingView, HistoryView
│   ├── AudioRecorder.swift       # AVAudioEngine recording
│   ├── TranscriptionManager.swift # WhisperKit wrapper with retry
│   ├── DatabaseManager.swift     # SQLite operations, App Groups
│   └── SharedStorage.swift       # UserDefaults legacy support
├── TranscriptKeyboard/
│   ├── KeyboardViewController.swift # Full keyboard with WhisperKit
│   └── Info.plist                # Mic permission, URL schemes
├── VoiceRecorderWidgetExtension/ # Live Activity
└── VoiceRecorder.xcodeproj/
```

## Database Schema

```sql
CREATE TABLE sessions (
    id TEXT PRIMARY KEY,
    created_at INTEGER NOT NULL,
    completed_at INTEGER,
    status TEXT DEFAULT 'recording',
    transcript TEXT,
    source TEXT DEFAULT 'app'  -- 'app' or 'keyboard'
);

CREATE TABLE chunks (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    session_id TEXT NOT NULL,
    chunk_number INTEGER NOT NULL,
    audio_blob BLOB NOT NULL,
    duration_ms INTEGER,
    created_at INTEGER NOT NULL
);
```

## Setup

1. Open `VoiceRecorder.xcodeproj` in Xcode
2. Build and run
3. Settings > General > Keyboard > Keyboards > Add "Transcript"
4. Enable "Allow Full Access" for microphone

## URL Schemes

- `brainphart://edit` - Edit latest transcript
- `brainphart://edit?session=<UUID>` - Edit specific session

## Roadmap

- [ ] BrainPhart Crisis App - voice-triggered prompts
- [ ] Start session / End of day workflows
- [ ] MD editing and export
- [ ] Calendar/Reminders integration via regex
- [ ] Vector embeddings for search

## License

Proprietary - Extrophi / I Am Codio
