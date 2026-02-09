//
//  VoiceRecorderApp.swift
//  VoiceRecorder
//
//  macOS app entry point.
//  - Initialises StorageBridge and whisper model on launch.
//  - Registers global hotkey (Cmd+Shift+R) via NSEvent monitor.
//  - Opens the main history window via WindowGroup.
//  - Runs crash recovery for orphaned sessions on first launch.
//

import SwiftUI
import AppKit
import VoiceRecorderBridge

@main
struct VoiceRecorderApp: App {
    // MARK: - State

    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @State private var appState = AppState()

    /// Status-bar item for menu-bar presence (optional).
    @State private var statusItem: NSStatusItem?

    // MARK: - Body

    var body: some Scene {
        WindowGroup("BrainPhart Voice") {
            ContentView()
                .environment(appState)
                .onAppear {
                    appDelegate.appState = appState
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
            appState.setError("Whisper model not found (\(Config.whisperModelFilename)) — transcription disabled")
            appState.isModelLoaded = false
            return
        }

        let success = appState.whisperBridge.loadModel(path)
        if success {
            log.info("Whisper model loaded from: \(path)")
            appState.isModelLoaded = true
        } else {
            appState.setError("Failed to load whisper model from: \(path)")
            appState.isModelLoaded = false
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

    /// Registers Cmd+Shift+R as a system-wide hotkey to toggle recording.
    private func registerGlobalHotkey() {
        NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { event in
            let requiredFlags: NSEvent.ModifierFlags = [.command, .shift]
            let hasFlags = event.modifierFlags.contains(requiredFlags)
            let isR = event.keyCode == 15  // R key
            if hasFlags && isR {
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
            let isR = event.keyCode == 15
            if hasFlags && isR {
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
                                   accessibilityDescription: "BrainPhart Voice")
        }

        let menu = NSMenu()
        menu.addItem(withTitle: "Toggle Recording (Cmd+Shift+R)",
                     action: #selector(NSApplication.shared.toggleRecordingMenuItem(_:)),
                     keyEquivalent: "")
        menu.addItem(.separator())
        menu.addItem(withTitle: "Quit BrainPhart Voice",
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

// MARK: - App Delegate

/// Handles graceful shutdown. Without this, exit() runs C++ static destructors
/// which try to free the ggml Metal device while its background residency-set
/// thread is still running — causing a crash (ggml_abort in ggml_metal_rsets_free).
@MainActor
class AppDelegate: NSObject, NSApplicationDelegate {
    var appState: AppState?

    func applicationWillTerminate(_ notification: Notification) {
        appState?.cleanup()
    }
}
