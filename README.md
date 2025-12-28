# BrainPhart Voice Recorder

Privacy-first voice recorder with local Whisper transcription.

## Platforms

- **iOS/iPadOS** - Swift/SwiftUI (App Store)
- **macOS** - Swift/SwiftUI (App Store + direct download)
- **Android** - Kotlin/Compose (Play Store) - planned

## Features

- Local Whisper transcription (no cloud)
- Model selection (tiny, base, small, medium, large)
- SQLite database storage
- Version control on edits (v1 raw, v2 edited, revert)
- Apple spell check
- Personal dictionary
- Auto-paste to cursor (multi-app)
- Floating recorder windows (micro/medium/full)
- History with search
- Audio playback with waveform
- Export to JSON/Markdown

## Architecture

```
brainphart-voice-recorder/
├── ios/                    # iOS/iPadOS app (Xcode project)
├── macos/                  # macOS app (Xcode project)
├── android/                # Android app (Kotlin/Compose)
├── shared/                 # Shared assets, prompts, models info
└── docs/                   # PRD, specs, App Store assets
```

## Development

### iOS/macOS
```bash
cd ios
open BrainPhartVoice.xcodeproj
```

### Android
```bash
cd android
./gradlew build
```

## License

Proprietary - Extrophi / I Am Codio
