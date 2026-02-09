# OSLog/Logger Reference (Fetched: 2026-02-09)

## Overview

Logger is Swift's modern unified logging API (iOS 14+, macOS 11+) providing low-overhead, device-persistent logging with privacy controls and performance measurement via signposts.

## Logger Initialization

```swift
import os

let logger = Logger(subsystem: "com.myapp.auth", category: "authentication")
```

- **subsystem**: Reverse-DNS string (typically your bundle ID) - must be unique across your app
- **category**: Functional area or feature name - organize related operations for filtering
- **Best practice**: Store as static/lazy properties to reuse instances

```swift
private static var subsystem = Bundle.main.bundleIdentifier!
static let audioLogger = Logger(subsystem: subsystem, category: "audio")
```

## Log Levels (in order of severity)

| Level | Persistence | Use Case |
|-------|-----------|----------|
| **debug** | None by default | Development/debugging only |
| **info** | None by default | Helpful non-essential information |
| **notice** | Persisted | Default level, general events |
| **error** | Persisted | Critical failures and errors |
| **fault** | Persisted | System-level or multi-process errors |

### Usage

```swift
logger.debug("Starting audio capture")
logger.info("Device: \(deviceName, privacy: .public)")
logger.notice("Recording paused by user")
logger.error("Failed to encode audio: \(error)")
logger.fault("Audio session crashed: \(systemError)")
```

## String Interpolation & Privacy

Default behavior redacts strings; integers, floats, booleans are visible.

### Privacy Levels

```swift
// Private (redacted as <private>)
logger.info("User: \(username, privacy: .private)")

// Public (visible)
logger.info("Device: \(device, privacy: .public)")

// Private with hash masking (for equality checks without exposing value)
logger.info("Account: \(accountNum, privacy: .private(mask: .hash))")
```

### With Formatting

```swift
logger.info("Name: \(name, align: .left(columns: 10)) Age: \(age, format: .fixed(precision: 2))")
```

## Signpost Integration (Performance Measurement)

Signposts measure task duration and integrate with Instruments for performance profiling:

```swift
let signposter = OSSignposter(subsystem: subsystem, category: "performance")

let signpostID = signposter.makeSignpostID()
let state = signposter.beginInterval("audio_encoding", id: signpostID)
// ... perform work ...
signposter.endInterval("audio_encoding", state)
```

Signposts appear in Console.app and Instruments' System Trace for low-impact performance analysis.

## Performance Characteristics

- **Overhead**: Negligible when disabled (compile-time optimization)
- **Persistence**: Notice, Error, Fault messages stored on device; Debug/Info available only via log collection tools
- **Filtering**: Console.app and Instruments allow real-time filtering by subsystem/category
- **String interpolation**: Compiler optimizes privacy redaction with zero runtime cost

## Best Practices: Subsystem & Category Naming

### Subsystem
- Use **Bundle.main.bundleIdentifier** or reverse-DNS format: `com.myapp.modulename`
- Must be unique per component
- Enables filtering across all app logs in Console.app

### Category
- Create one per **functional area**: "audio", "network", "database", "ui"
- Examples: "transcription", "pcm_buffer", "whisper_bridge"
- Allows granular filtering without excessive logger instances

### Avoid
- Generic names ("app", "main", "utils")
- Redundant subsystem+category pairs (one logger per feature)
- Dynamic category names in loops (create reusable instances)

## Code Example: BPH-002 Audio Logger

```swift
import os

class AudioManager {
    private static let subsystem = Bundle.main.bundleIdentifier ?? "com.brainphart.recorder"
    private static let audioLogger = Logger(subsystem: subsystem, category: "audio")
    private static let whisperLogger = Logger(subsystem: subsystem, category: "transcription")

    func startRecording(deviceName: String) {
        Self.audioLogger.notice("Recording started on device: \(deviceName, privacy: .public)")
    }

    func transcribePCM(sampleCount: Int) {
        let signposter = OSSignposter(subsystem: Self.subsystem, category: "performance")
        let id = signposter.makeSignpostID()
        let state = signposter.beginInterval("transcribe", id: id)

        Self.whisperLogger.debug("Transcribing \(sampleCount) samples")

        // ... transcription ...

        signposter.endInterval("transcribe", state)
        Self.whisperLogger.info("Transcription complete")
    }

    func logError(_ error: Error, context: String) {
        Self.audioLogger.error("[\(context, privacy: .public)] \(error.localizedDescription, privacy: .private)")
    }
}
```

## Viewing Logs

- **Xcode Console**: Automatically captures output during development
- **Console.app**: Filter by subsystem/category; view persisted logs post-crash
- **Command line**: `log stream --predicate 'subsystem == "com.myapp.audio"'`
- **Instruments**: Create custom signpost traces in System Trace tool

## References

- [Logger Apple Developer Documentation](https://developer.apple.com/documentation/os/logger)
- [OSLog Apple Developer Documentation](https://developer.apple.com/documentation/os/oslog)
- [OSSignposter Apple Developer Documentation](https://developer.apple.com/documentation/os/ossignposter)
- [OSLogPrivacy Apple Developer Documentation](https://developer.apple.com/documentation/os/oslogprivacy)
- [WWDC 2020: Explore Logging in Swift](https://developer.apple.com/videos/play/wwdc2020/10168/)
- [WWDC 2018: Measuring Performance Using Logging](https://developer.apple.com/videos/play/wwdc2018/405/)
- [OSLog Best Practices Guide](https://www.avanderlee.com/debugging/oslog-unified-logging/)
