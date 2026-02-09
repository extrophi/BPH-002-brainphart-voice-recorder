# AVAudioEngine Recording Reference (Fetched: 2026-02-09)

## Overview

AVAudioEngine provides low-latency, real-time audio processing for macOS. For microphone recording, you build an audio processing graph by connecting nodes and installing taps to capture audio buffers.

---

## AVAudioEngine Setup for Recording

### Basic Initialization

```swift
import AVFoundation

let audioEngine = AVAudioEngine()
let inputNode = audioEngine.inputNode
```

### Audio Session Configuration

```swift
let audioSession = AVAudioSession.sharedInstance()
try audioSession.setCategory(.record, options: [.defaultToSpeaker, .allowBluetooth])
try audioSession.setActive(true, options: .notifyOthersOnDeactivation)
```

### Get Input Format (Critical: Use outputFormat, NOT inputFormat)

```swift
// IMPORTANT: On macOS, inputFormat may return nil or 0 channels
let inputFormat = inputNode.outputFormat(forBus: 0)!
print("Input format: \(inputFormat.sampleRate) Hz, \(inputFormat.channelCount) ch")
```

---

## installTap(onBus:bufferSize:format:) API

### Method Signature

```swift
func installTap(onBus bus: AVAudioNodeBus,
               bufferSize: AVAudioFrameCount,
               format: AVAudioFormat?,
               block: @escaping AVAudioNodeTapBlock)
```

### Critical Rules

1. **Format must match input format**: Use `nil` to auto-match `inputNode.outputFormat(forBus: 0)`, or pass that exact format
2. **macOS quirk**: Use `outputFormat(forBus:)` not `inputFormat` — inputFormat may be nil
3. **Buffer size is a suggestion**: System may choose different size [100-400 ms]; do not assume exact match
4. **Callback**: Receives `AVAudioPCMBuffer` and `AVAudioTime`

### Installation Pattern

```swift
let inputFormat = inputNode.outputFormat(forBus: 0)!

inputNode.installTap(onBus: 0, bufferSize: 4096, format: nil) { buffer, time in
    // buffer is in inputFormat
    handleAudioBuffer(buffer)
}

audioEngine.prepare()
try audioEngine.start()
```

---

## AVAudioFormat for 16 kHz Mono Float32

### Creating the Target Format

```swift
let targetFormat = AVAudioFormat(
    commonFormat: .pcmFormatFloat32,
    sampleRate: 16000,
    channels: 1,
    interleaved: false
)!
```

### Why These Settings?

| Property | Value | Reason |
|----------|-------|--------|
| Format | Float32 | Whisper.cpp standard; memory layout predictable |
| Sample Rate | 16000 | Whisper.cpp expects 16 kHz |
| Channels | 1 | Mono reduces data; Whisper processes mono |
| Interleaved | false | AVAudioEngine requires non-interleaved |

### Creating a Buffer

```swift
let buffer = AVAudioPCMBuffer(pcmFormat: targetFormat, frameCapacity: 4096)!
```

---

## AVAudioConverter for Sample Rate Conversion

Microphone input is typically 48 kHz; convert to 16 kHz mono.

### Initialization

```swift
let inputFormat = inputNode.outputFormat(forBus: 0)!
let targetFormat = AVAudioFormat(
    commonFormat: .pcmFormatFloat32,
    sampleRate: 16000, channels: 1, interleaved: false)!

guard let converter = AVAudioConverter(from: inputFormat, to: targetFormat) else {
    fatalError("Cannot create converter")
}
```

### Conversion in Tap Block

```swift
inputNode.installTap(onBus: 0, bufferSize: 4096, format: nil) { buffer, time in
    let outFrames = AVAudioFrameCount(Double(buffer.frameLength) *
                                      targetFormat.sampleRate / inputFormat.sampleRate)
    guard let outBuf = AVAudioPCMBuffer(pcmFormat: targetFormat,
                                        frameCapacity: outFrames) else { return }

    var error: NSError?
    converter.convert(to: outBuf, error: &error) { _, outStatus in
        outStatus.pointee = .haveData
        return buffer
    }

    guard error == nil else {
        print("Conversion error: \(error!)")
        return
    }

    // outBuf is now 16 kHz mono Float32
    processAudio(outBuf)
}
```

---

## Common Pitfalls & Solutions

### 1. Wrong Format Method
```swift
// WRONG: inputFormat may be nil on macOS
let fmt = inputNode.inputFormat(forBus: 0)

// CORRECT
let fmt = inputNode.outputFormat(forBus: 0)!
```

### 2. Format Mismatch in Tap
```swift
// WRONG: targetFormat won't match inputFormat
inputNode.installTap(onBus: 0, bufferSize: 4096, format: targetFormat)

// CORRECT: use nil or exact match
inputNode.installTap(onBus: 0, bufferSize: 4096, format: nil)
```

### 3. Interleaved Stereo (Crashes)
```swift
// WRONG: Interleaved stereo crashes with AVAudioEngine
let fmt = AVAudioFormat(commonFormat: .pcmFormatFloat32,
                        sampleRate: 16000, channels: 2, interleaved: true)

// CORRECT: Non-interleaved only
let fmt = AVAudioFormat(commonFormat: .pcmFormatFloat32,
                        sampleRate: 16000, channels: 2, interleaved: false)
```

### 4. Assuming Exact Buffer Size
```swift
// WRONG: buffer.frameLength may differ from request
let sz = 4096
inputNode.installTap(onBus: 0, bufferSize: AVAudioFrameCount(sz)) { buffer, _ in
    assert(buffer.frameLength == sz)  // MAY FAIL
}

// CORRECT: Use actual frame length
inputNode.installTap(onBus: 0, bufferSize: 4096) { buffer, _ in
    let actual = buffer.frameLength
    processFrames(actual)
}
```

### 5. macOS Sandboxing
Add to `Info.plist`:
```xml
<key>NSMicrophoneUsageDescription</key>
<string>Record audio for transcription</string>
```
Enable "Audio Input" under App Sandbox → Hardware in Xcode.

---

## Complete Recording Example

```swift
class AudioRecorder {
    let audioEngine = AVAudioEngine()
    var converter: AVAudioConverter?
    var targetFormat: AVAudioFormat?

    func startRecording() throws {
        let inputNode = audioEngine.inputNode
        let inputFormat = inputNode.outputFormat(forBus: 0)!

        targetFormat = AVAudioFormat(
            commonFormat: .pcmFormatFloat32, sampleRate: 16000,
            channels: 1, interleaved: false)!

        guard let conv = AVAudioConverter(from: inputFormat, to: targetFormat!) else {
            throw NSError(domain: "AudioRecorder", code: -1)
        }
        self.converter = conv

        inputNode.installTap(onBus: 0, bufferSize: 4096, format: nil) { [weak self] buf, _ in
            self?.handleAudioBuffer(buf)
        }

        try audioEngine.start()
    }

    func handleAudioBuffer(_ buffer: AVAudioPCMBuffer) {
        guard let converter = converter, let targetFormat = targetFormat else { return }

        let outFrames = AVAudioFrameCount(Double(buffer.frameLength) *
                                          targetFormat.sampleRate / buffer.format.sampleRate)
        guard let outBuf = AVAudioPCMBuffer(pcmFormat: targetFormat,
                                            frameCapacity: outFrames) else { return }

        var error: NSError?
        converter.convert(to: outBuf, error: &error) { _, outStatus in
            outStatus.pointee = .haveData
            return buffer
        }

        guard error == nil else { return }

        // outBuf is 16 kHz mono Float32 PCM
        // Send to Whisper: outBuf.floatChannelData![0], frameLength
    }
}
```

---

## Key Differences: macOS vs iOS

| Aspect | macOS | iOS |
|--------|-------|-----|
| outputFormat | Use this | Use this |
| inputFormat | May be nil | Reliable |
| Sandboxing | App Sandbox required | Background Modes capability |

---

## Sources

- [installTap(onBus:bufferSize:format:block:)](https://developer.apple.com/documentation/avfaudio/avaudionode/1387122-installtap)
- [AVAudioFormat Documentation](https://developer.apple.com/documentation/avfaudio/avaudioformat)
- [AVAudioConverter Documentation](https://developer.apple.com/documentation/avfaudio/avaudioconverter)
- [TN3136: AVAudioConverter Sample Rate Conversions](https://developer.apple.com/documentation/technotes/tn3136-avaudioconverter-performing-sample-rate-conversions)
- [TensorFlow AudioInputManager Example](https://github.com/tensorflow/examples/blob/master/lite/examples/speech_commands/ios/SpeechCommands/AudioInputManager/AudioInputManager.swift)
- [AVAEMixerSample Swift Translation](https://github.com/ooper-shlab/AVAEMixerSample-Swift)
- [whisper.cpp Issue #2008: AVAudioNode Buffer Format](https://github.com/ggerganov/whisper.cpp/issues/2008)
