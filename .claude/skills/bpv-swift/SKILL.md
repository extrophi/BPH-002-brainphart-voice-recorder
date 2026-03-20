---
name: bpv-swift
description: BrainPhart Voice recorder - Swift AVAudio whisper.cpp. Load before touching any BPH-002 code. Built from actual source files not training data.
---

# BrainPhart Voice Swift Skill

Project: /Users/kjd/01-projects/BPH-002-brainphart-voice-recorder

## Build Order

    cmake -B build -DCMAKE_BUILD_TYPE=Release -DWHISPER_METAL=ON
    cmake --build build -j
    swift build -c release 2>&1
    swift build -c release 2>&1 | grep "error:" | wc -l
    .build/release/VoiceRecorder

## Auto-Paste Bug Fix

File: Sources/VoiceRecorder/AppState.swift line 280

DELETE this:

    if UserDefaults.standard.bool(forKey: "autoPasteEnabled") {
        AutoPaste.pasteText(transcript)
    } else {
        NSPasteboard.general.setString(transcript, forType: .string)
    }

REPLACE WITH:

    AutoPaste.pasteText(transcript)

## Architecture

    Swift UI       Sources/VoiceRecorder/
    Obj-C++ Bridge Sources/VoiceRecorderBridge/
    C++ Core       Sources/VoiceRecorderCore/

## AVAudioEngine Rules

    Format: pcmFormatFloat32 16000Hz channels:1 interleaved:false
    Check outputBuffer.frameLength NOT status enum
    WAV audioFormat = 3 not 1

## NSPanel

    hidesOnDeactivate = false
    level = .floating
    becomesKeyOnlyIfNeeded = true

## Thread Safety

    Audio thread  AudioBuffer NSLock
    AppState      @MainActor
    Callbacks     Task { @MainActor in }

## Never

    DONE without launching app
    UserDefaults gate on auto-paste
    Trust AVAudioConverter status enum
    Edit file more than 5 times without swift build
    Hardcode paths
    Python whisper instead of whisper.cpp Metal
