//
//  VoiceRecorderApp.swift
//  VoiceRecorder
//
//  macOS app entry point.
//  - Initialises StorageBridge and whisper model on launch.
//  - Registers global hotkey (Cmd+Shift+Space) via NSEvent monitor.
//  - Opens the main history window via WindowGroup.
//  - Runs crash recovery for orphaned sessions on first launch.
//

import SwiftUI
import AppKit
import VoiceRecorderBridge

@main
struct VoiceRecorderApp: App {
    // MARK: - State

    @State private var appState = AppState()

    /// Status-bar item for menu-bar presence (optional).
    @State private var statusItem: NSStatusItem?

    // MARK: - Body

    var body: some Scene {
        WindowGroup("Voice Recorder") {
            ContentView()
                .environment(appState)
                .onAppear {
                    bootstrapOnFirstAppear()
                }
        }
        .defaultSize(width: 720, height: 520)
    }

    // MARK: - Bootstrap

    /// Called once when the first window appears. Performs all launch-time
    /// initialisation that requires the run-loop to be active.
    private func bootstrapOnFirstAppear() {
        loadWhisperModel()
        recoverOrphanedSessions()
        registerGlobalHotkey()
        installMenuBarItem()
        appState.showFloatingOverlay()
    }

    // MARK: - Whisper Model

    private func loadWhisperModel() {
        guard let path = Config.resolveModelPath() else {
            log.error("Could not locate whisper model (\(Config.whisperModelFilename)) in any candidate path.")
            return
        }

        let success = appState.whisperBridge.loadModel(path)
        if success {
            log.info("Whisper model loaded from: \(path)")
        } else {
            log.error("Failed to load whisper model from: \(path)")
        }
    }

    // MARK: - Crash Recovery

    /// On launch, any session left in "recording" status is orphaned (the app
    /// crashed or was force-quit). Re-process them so no audio is lost.
    private func recoverOrphanedSessions() {
        let orphaned = appState.storageBridge.getOrphanedSessions()
        guard let sessions = orphaned as? [VRSession], !sessions.isEmpty else { return }

        log.info("Recovering \(sessions.count) orphaned session(s)...")
        for session in sessions {
            appState.retryTranscription(sessionId: session.sessionId)
        }
    }

    // MARK: - Global Hotkey

    /// Registers Cmd+Shift+Space as a system-wide hotkey to toggle recording.
    private func registerGlobalHotkey() {
        NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { event in
            let requiredFlags: NSEvent.ModifierFlags = [.command, .shift]
            let hasFlags = event.modifierFlags.contains(requiredFlags)
            let isSpace = event.keyCode == 49  // spacebar
            if hasFlags && isSpace {
                Task { @MainActor in
                    appState.toggleRecording()
                }
            }
        }

        // Also register a local monitor so the hotkey works while the app is
        // in the foreground.
        NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            let requiredFlags: NSEvent.ModifierFlags = [.command, .shift]
            let hasFlags = event.modifierFlags.contains(requiredFlags)
            let isSpace = event.keyCode == 49
            if hasFlags && isSpace {
                Task { @MainActor in
                    appState.toggleRecording()
                }
                return nil  // consume the event
            }
            return event
        }
    }

    // MARK: - Menu Bar

    private func installMenuBarItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        if let button = item.button {
            button.image = NSImage(systemSymbolName: "mic.fill",
                                   accessibilityDescription: "Voice Recorder")
        }

        let menu = NSMenu()
        menu.addItem(withTitle: "Toggle Recording (Cmd+Shift+Space)",
                     action: #selector(NSApplication.shared.toggleRecordingMenuItem(_:)),
                     keyEquivalent: "")
        menu.addItem(.separator())
        menu.addItem(withTitle: "Quit Voice Recorder",
                     action: #selector(NSApplication.shared.terminate(_:)),
                     keyEquivalent: "q")
        item.menu = menu

        statusItem = item
    }
}

// MARK: - NSApplication helpers

extension NSApplication {
    /// Selector target for the menu-bar "Toggle Recording" item.
    @objc func toggleRecordingMenuItem(_ sender: Any?) {
        // Post a notification that AppState can pick up if needed.
        NotificationCenter.default.post(name: .toggleRecordingAction, object: nil)
    }
}

extension Notification.Name {
    static let toggleRecordingAction = Notification.Name("com.voicerecorder.toggleRecording")
}
