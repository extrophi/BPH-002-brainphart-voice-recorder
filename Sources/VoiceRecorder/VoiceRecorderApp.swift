//
//  VoiceRecorderApp.swift
//  VoiceRecorder
//
//  macOS app entry point.
//  - Initialises StorageBridge and whisper model on launch.
//  - Registers global hotkey (Option+Shift) via NSEvent flagsChanged monitor.
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
        // Must switch to regular policy so the window can appear
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)

        for window in self.windows where !(window is NSPanel) {
            window.makeKeyAndOrderFront(nil)
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
    private var flagsMonitor: Any?
    private var escapeMonitor: Any?
    private var modifiersDown = false
    private var keyDownTimestamp: Date?
    private var lastEscapeTimestamp: Date?

    func applicationDidFinishLaunching(_ notification: Notification) {
        installMenuBarItem()
        registerGlobalHotkey()
        registerEscapeMonitor()

        // Set accessory policy AFTER menu bar item is installed.
        // This hides the dock icon and prevents the WindowGroup from
        // showing its window on launch. The menu bar item survives
        // because it was created before the policy change.
        NSApp.setActivationPolicy(.accessory)

        // Watch for window close to switch back to accessory mode
        NotificationCenter.default.addObserver(
            forName: NSWindow.willCloseNotification,
            object: nil, queue: .main
        ) { [weak self] notification in
            guard let window = notification.object as? NSWindow,
                  !(window is NSPanel) else { return }
            // Delay so the close animation finishes
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                // Only go back to accessory if no visible windows remain
                let hasVisible = NSApp.windows.contains { !($0 is NSPanel) && $0.isVisible }
                if !hasVisible {
                    NSApp.setActivationPolicy(.accessory)
                }
            }
        }

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
        menu.addItem(withTitle: "Toggle Recording (⌥⇧)",
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

    // MARK: - Global Hotkey (Option+Shift via flagsChanged monitor)

    /// Minimum hold duration (seconds) to distinguish a hold from a tap.
    private static let holdThreshold: TimeInterval = 0.3

    /// The exact modifier flags we're looking for (Option + Shift, nothing else).
    private static let targetModifiers: NSEvent.ModifierFlags = [.option, .shift]
    private static let modifierMask: NSEvent.ModifierFlags = [.option, .shift, .command, .control]

    private func registerGlobalHotkey() {
        flagsMonitor = NSEvent.addGlobalMonitorForEvents(matching: .flagsChanged) { [weak self] event in
            Task { @MainActor [weak self] in
                self?.handleFlagsChanged(event)
            }
        }
    }

    private func handleFlagsChanged(_ event: NSEvent) {
        let active = event.modifierFlags.intersection(AppDelegate.modifierMask)
        let matched = active == AppDelegate.targetModifiers

        if matched && !modifiersDown {
            // Option+Shift just pressed
            modifiersDown = true
            keyDownTimestamp = Date()

            switch appSettings.recordingMode {
            case .toggle:
                appState.toggleRecording()
            case .pushToTalk:
                if !appState.isRecording {
                    appState.startRecording()
                }
            }
        } else if !matched && modifiersDown {
            // Option+Shift released
            modifiersDown = false

            if appSettings.recordingMode == .pushToTalk, appState.isRecording {
                let holdDuration = Date().timeIntervalSince(keyDownTimestamp ?? Date())
                if holdDuration >= AppDelegate.holdThreshold {
                    appState.stopRecording()
                } else {
                    appState.cancelRecording()
                }
            }
            keyDownTimestamp = nil
        }
    }

    // MARK: - Double-Escape to Cancel Recording

    /// Maximum interval between two Escape presses to count as double-tap.
    private static let doubleEscapeInterval: TimeInterval = 0.4

    private func registerEscapeMonitor() {
        escapeMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard event.keyCode == 53 else { return } // 53 = Escape
            Task { @MainActor [weak self] in
                self?.handleEscapePress()
            }
        }
    }

    private func handleEscapePress() {
        let now = Date()
        if let last = lastEscapeTimestamp,
           now.timeIntervalSince(last) < AppDelegate.doubleEscapeInterval {
            // Double-Escape: cancel recording
            if appState.isRecording {
                appState.cancelRecording()
            }
            lastEscapeTimestamp = nil
        } else {
            lastEscapeTimestamp = now
        }
    }
}
