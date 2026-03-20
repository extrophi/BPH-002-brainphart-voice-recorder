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
import ApplicationServices
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
        .commands {
            CommandGroup(replacing: .appInfo) {
                Button("About BrainPhart Voice") {
                    NSApp.orderFrontStandardAboutPanel(options: [
                        .applicationName: "BrainPhart Voice",
                        .applicationVersion: "0.2.0",
                    ])
                }
            }

            CommandGroup(replacing: .newItem) {
                Button("New Recording") {
                    NotificationCenter.default.post(name: .toggleRecordingAction, object: nil)
                }
                .keyboardShortcut("r", modifiers: .command)
            }

            CommandGroup(replacing: .help) {
                Button("BrainPhart Voice Help") {
                    // Placeholder — could open docs URL
                }
            }
        }

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
    private var localFlagsMonitor: Any?
    private var escapeMonitor: Any?
    private var modifiersDown = false
    private var keyDownTimestamp: Date?
    private var lastEscapeTimestamp: Date?

    func applicationDidFinishLaunching(_ notification: Notification) {
        installMenuBarItem()
        checkPermissionsOnLaunch()
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

        // Overlay is shown on-demand when recording starts (not at launch).
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard appState.isRecording else { return .terminateNow }

        let alert = NSAlert()
        alert.messageText = "Recording in Progress"
        alert.informativeText = "A recording is in progress. Quitting will stop the recording and attempt to transcribe it. Are you sure?"
        alert.addButton(withTitle: "Quit")
        alert.addButton(withTitle: "Cancel")
        alert.alertStyle = .warning

        let response = alert.runModal()
        if response == .alertFirstButtonReturn {
            appState.stopRecording()
            return .terminateNow
        }
        return .terminateCancel
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
            if let url = Bundle.module.url(forResource: "brain-menubar", withExtension: "png"),
               let img = NSImage(contentsOf: url) {
                img.isTemplate = true
                img.size = NSSize(width: 18, height: 18)
                button.image = img
            } else {
                button.image = NSImage(systemSymbolName: "mic.fill",
                                       accessibilityDescription: "BrainPhart Voice")
            }
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

    // MARK: - Permission Checks

    /// Check Input Monitoring, Accessibility, and (macOS 15+) PostEvent permissions on launch.
    /// macOS Tahoe (26) resets TCC permissions during upgrades, so the app
    /// must detect this and guide the user to re-grant them.
    /// On macOS 15+, PostEvent is a SEPARATE TCC permission from Accessibility —
    /// both must be granted for CGEvent posting (auto-paste) to work.
    private func checkPermissionsOnLaunch() {
        let hasInputMonitoring = CGPreflightListenEventAccess()
        let hasAccessibility = AXIsProcessTrusted()

        // macOS 15+ has a SEPARATE PostEvent TCC permission from Accessibility.
        // Both are required: Accessibility for AX APIs, PostEvent for CGEvent posting.
        let hasPostEvent: Bool
        if #available(macOS 15, *) {
            hasPostEvent = CGPreflightPostEventAccess()
        } else {
            hasPostEvent = hasAccessibility
        }

        log.info("Permission check — InputMonitoring: \(hasInputMonitoring), Accessibility: \(hasAccessibility), PostEvent: \(hasPostEvent)")

        // Request PostEvent permission proactively if not granted (macOS 15+).
        // This prompts the system dialog upfront rather than on first paste attempt.
        if #available(macOS 15, *), !hasPostEvent {
            let granted = CGRequestPostEventAccess()
            log.info("CGRequestPostEventAccess result: \(granted)")
        }

        if !hasInputMonitoring {
            CGRequestListenEventAccess()
            appState.setError("Input Monitoring permission required for global hotkey (⌥⇧). Grant in System Settings > Privacy & Security > Input Monitoring, then relaunch.")
        }

        if !hasAccessibility {
            showPermissionAlert(
                title: "Accessibility Permission Required",
                message: """
                    BrainPhart Voice needs Accessibility permission to auto-paste \
                    transcriptions at your cursor.

                    After a fresh install or macOS update, you may need to:
                    1. Open System Settings > Privacy & Security > Accessibility
                    2. Remove any old BrainPhart Voice entry
                    3. Add the new one from /Applications/
                    4. Relaunch the app
                    """,
                settingsURL: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"
            )
        }
    }

    private func showPermissionAlert(title: String, message: String, settingsURL: String) {
        // Temporarily show the app so the alert is visible.
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)

        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Open System Settings")
        alert.addButton(withTitle: "Later")

        let response = alert.runModal()
        if response == .alertFirstButtonReturn {
            if let url = URL(string: settingsURL) {
                NSWorkspace.shared.open(url)
            }
        }

        // Switch back to accessory mode — installMenuBarItem runs before this.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            NSApp.setActivationPolicy(.accessory)
        }
    }

    // MARK: - Global Hotkey (Option+Shift via flagsChanged monitor)

    /// Minimum hold duration (seconds) to distinguish a hold from a tap.
    private static let holdThreshold: TimeInterval = 0.3

    /// The exact modifier flags we're looking for (Option + Shift, nothing else).
    private static let targetModifiers: NSEvent.ModifierFlags = [.option, .shift]
    private static let modifierMask: NSEvent.ModifierFlags = [.option, .shift, .command, .control]

    private func registerGlobalHotkey() {
        // Global monitor: receives events when app is NOT frontmost.
        // Requires Input Monitoring permission (TCC ListenEvent).
        flagsMonitor = NSEvent.addGlobalMonitorForEvents(matching: .flagsChanged) { [weak self] event in
            Task { @MainActor [weak self] in
                self?.handleFlagsChanged(event)
            }
        }

        if flagsMonitor == nil {
            // Global monitor returned nil — TCC Input Monitoring permission is denied or was reset.
            // The app can still record when it is frontmost (localFlagsMonitor works without TCC),
            // but the global hotkey will not fire from other apps.
            appState.setError("Input Monitoring permission denied — global hotkey (⌥⇧) disabled. Grant in System Settings > Privacy & Security > Input Monitoring.")
            showPermissionAlert(
                title: "Input Monitoring Permission Required",
                message: """
                    BrainPhart Voice could not register the global hotkey (⌥⇧).

                    This happens when Input Monitoring permission is denied or was reset \
                    (e.g. after a macOS or Xcode update).

                    To fix this:
                    1. Open System Settings > Privacy & Security > Input Monitoring
                    2. After a fresh install, remove the old entry and re-add from /Applications/
                    3. Enable BrainPhart Voice (or re-add it)
                    4. Relaunch the app

                    Until then, the hotkey will only work while BrainPhart Voice is the active app.
                    """,
                settingsURL: "x-apple.systempreferences:com.apple.preference.security?Privacy_ListenEvent"
            )
        }

        // Local monitor: receives events when app IS frontmost.
        // Does NOT require Input Monitoring permission.
        localFlagsMonitor = NSEvent.addLocalMonitorForEvents(matching: .flagsChanged) { [weak self] event in
            Task { @MainActor [weak self] in
                self?.handleFlagsChanged(event)
            }
            return event
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
