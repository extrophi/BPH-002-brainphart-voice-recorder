//
//  VoiceRecorderApp.swift
//  VoiceRecorder
//
//  macOS app entry point.
//  - Initialises StorageBridge and whisper model on launch.
//  - Registers global hotkey (Option+Shift+R) via HotKey library (Carbon RegisterEventHotKey).
//  - Opens the main history window via WindowGroup.
//  - Runs crash recovery for orphaned sessions on first launch.
//

import SwiftUI
import AppKit
import HotKey
import VoiceRecorderBridge

@main
struct VoiceRecorderApp: App {
    // MARK: - State

    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    // MARK: - Body

    var body: some Scene {
        WindowGroup("BrainPhart Voice") {
            ContentView()
                .environment(appDelegate.appState)
                .onAppear {
                    loadWhisperModel()
                    recoverOrphanedSessions()
                }
        }
        .defaultSize(width: 720, height: 520)

        Settings {
            SettingsView()
                .environment(appDelegate.appSettings)
        }
    }

    // MARK: - Whisper Model

    private func loadWhisperModel() {
        let appState = appDelegate.appState
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
    /// Very short recordings (< 1s) are silently deleted — they can't produce
    /// meaningful transcriptions and would otherwise show confusing empty results.
    private func recoverOrphanedSessions() {
        let appState = appDelegate.appState
        let orphaned = appState.storageBridge.getOrphanedSessions()
        guard let sessions = orphaned as? [VRSession], !sessions.isEmpty else { return }

        log.info("Recovering \(sessions.count) orphaned session(s)...")
        for session in sessions {
            let pcmData = appState.storageBridge.getAudioForSession(session.sessionId)
            let byteCount = pcmData?.count ?? 0
            let sampleCount = byteCount / MemoryLayout<Float>.size
            let durationSeconds = Float(sampleCount) / Float(Config.transcriptionSampleRate)

            if durationSeconds < Config.minimumTranscriptionDuration {
                log.info("Orphaned session \(session.sessionId) too short (\(String(format: "%.1f", durationSeconds))s) — deleting")
                appState.deleteSession(sessionId: session.sessionId)
                continue
            }

            log.info("Orphaned session \(session.sessionId): \(String(format: "%.1f", durationSeconds))s — attempting transcription")
            appState.retryTranscription(sessionId: session.sessionId)
        }
    }
}

// MARK: - NSApplication helpers

extension NSApplication {
    /// Selector target for the menu-bar "Toggle Recording" item.
    @objc func toggleRecordingMenuItem(_ sender: Any?) {
        NotificationCenter.default.post(name: .toggleRecordingAction, object: nil)
    }

    /// Selector target for the menu-bar "Settings..." item.
    @objc func showSettingsMenuItem(_ sender: Any?) {
        // Temporarily switch to regular activation policy so the Settings
        // window can become key and visible.
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)

        if #available(macOS 14, *) {
            NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
        } else {
            NSApp.sendAction(Selector(("showPreferencesWindow:")), to: nil, from: nil)
        }

        // Switch back to accessory after a short delay so the dock icon
        // disappears once the settings window is closed.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            NSApp.setActivationPolicy(.accessory)
        }
    }

    /// Selector target for the menu-bar "Show History" item.
    @objc func showHistoryMenuItem(_ sender: Any?) {
        for window in self.windows where !(window is NSPanel) {
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }
    }
}

extension Notification.Name {
    static let toggleRecordingAction = Notification.Name("com.voicerecorder.toggleRecording")
}

// MARK: - App Delegate

/// Handles launch bootstrap, menu bar setup, and graceful shutdown.
/// Bootstrap happens in applicationDidFinishLaunching so the menu bar item
/// is installed before switching to .accessory activation policy — this
/// prevents the history window from flashing on screen.
@MainActor
class AppDelegate: NSObject, NSApplicationDelegate {
    let appState = AppState()
    let appSettings = AppSettings()
    private var statusItem: NSStatusItem?
    private var hotKey: HotKey?
    private var keyDownTimestamp: Date?

    func applicationDidFinishLaunching(_ notification: Notification) {
        installMenuBarItem()
        registerGlobalHotkey()

        // Set accessory policy AFTER menu bar item is installed.
        // This hides the dock icon and prevents the WindowGroup from
        // showing its window on launch. The menu bar item survives
        // because it was created before the policy change.
        NSApp.setActivationPolicy(.accessory)

        appState.showFloatingOverlay()
    }

    func applicationWillTerminate(_ notification: Notification) {
        appState.cleanup()
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag {
            sender.showHistoryMenuItem(nil)
        }
        return true
    }

    // MARK: - Menu Bar

    private func installMenuBarItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        if let button = item.button {
            button.image = NSImage(systemSymbolName: "mic.fill",
                                   accessibilityDescription: "BrainPhart Voice")
        }

        let menu = NSMenu()
        menu.addItem(withTitle: "Toggle Recording (⌥⇧R)",
                     action: #selector(NSApplication.shared.toggleRecordingMenuItem(_:)),
                     keyEquivalent: "")
        menu.addItem(withTitle: "Show History",
                     action: #selector(NSApplication.shared.showHistoryMenuItem(_:)),
                     keyEquivalent: "h")
        menu.addItem(.separator())
        let settingsItem = NSMenuItem(title: "Settings...",
                                      action: #selector(NSApplication.shared.showSettingsMenuItem(_:)),
                                      keyEquivalent: ",")
        menu.addItem(settingsItem)
        menu.addItem(.separator())
        menu.addItem(withTitle: "Quit BrainPhart Voice",
                     action: #selector(NSApplication.shared.terminate(_:)),
                     keyEquivalent: "q")
        item.menu = menu

        statusItem = item
    }

    // MARK: - Global Hotkey (Carbon RegisterEventHotKey via HotKey library)

    /// Minimum hold duration (seconds) to distinguish a hold from a tap.
    private static let holdThreshold: TimeInterval = 0.3

    private func registerGlobalHotkey() {
        let hk = HotKey(key: .r, modifiers: [.option, .shift])

        hk.keyDownHandler = { [weak self] in
            guard let self else { return }
            self.keyDownTimestamp = Date()

            switch self.appSettings.recordingMode {
            case .toggle:
                self.appState.toggleRecording()
            case .pushToTalk:
                if !self.appState.isRecording {
                    self.appState.startRecording()
                }
            }
        }

        hk.keyUpHandler = { [weak self] in
            guard let self else { return }
            guard self.appSettings.recordingMode == .pushToTalk else { return }
            guard self.appState.isRecording else { return }

            let holdDuration = Date().timeIntervalSince(self.keyDownTimestamp ?? Date())
            if holdDuration >= AppDelegate.holdThreshold {
                self.appState.stopRecording()
            } else {
                self.appState.cancelRecording()
            }
            self.keyDownTimestamp = nil
        }

        self.hotKey = hk
    }
}
