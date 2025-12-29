import SwiftUI
#if os(macOS)
import AppKit
import Carbon.HIToolbox
#else
import UIKit
#endif

@main
struct VoiceRecorderApp: App {
    #if os(macOS)
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    #else
    @UIApplicationDelegateAdaptor(iOSAppDelegate.self) var appDelegate
    #endif

    var body: some Scene {
        WindowGroup {
            MainContentView()
                .environmentObject(AppState.shared)
                .environmentObject(RecordingCoordinator.shared)
        }
        #if os(macOS)
        .windowStyle(.hiddenTitleBar)
        #endif
    }
}

// MARK: - iOS App Delegate

#if os(iOS)
class iOSAppDelegate: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication, configurationForConnecting connectingSceneSession: UISceneSession, options: UIScene.ConnectionOptions) -> UISceneConfiguration {
        let config = UISceneConfiguration(name: nil, sessionRole: connectingSceneSession.role)
        config.delegateClass = SceneDelegate.self
        return config
    }
}

class SceneDelegate: NSObject, UIWindowSceneDelegate {
    var window: UIWindow?

    func scene(_ scene: UIScene, willConnectTo session: UISceneSession, options connectionOptions: UIScene.ConnectionOptions) {
        // Handle URL if app was launched via URL
        if let url = connectionOptions.urlContexts.first?.url {
            handleURL(url)
        }
    }

    func scene(_ scene: UIScene, openURLContexts URLContexts: Set<UIOpenURLContext>) {
        // Handle URL when app is already running
        if let url = URLContexts.first?.url {
            handleURL(url)
        }
    }

    private func handleURL(_ url: URL) {
        let appGroupID = "group.com.brainphart.voicerecorder"

        if url.host == "edit" {
            // Check for session parameter in URL
            let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
            let sessionId = components?.queryItems?.first(where: { $0.name == "session" })?.value

            Task { @MainActor in
                if let sessionId = sessionId {
                    // Load transcript from database using session ID
                    let sessions = DatabaseManager.shared.getAllSessions()
                    if let session = sessions.first(where: { $0.id == sessionId }) {
                        // Session found - use its transcript (even if empty)
                        AppState.shared.editingTranscript = session.transcript ?? ""
                        AppState.shared.editingSessionId = sessionId
                        AppState.shared.showEditView = true
                        print("[App] Editing session \(sessionId)")
                    } else {
                        // Session not found in database - fall back to UserDefaults
                        // This can happen if there's a timing issue between keyboard and app
                        print("[App] Session \(sessionId) not found in database, using fallback")
                        if let defaults = UserDefaults(suiteName: appGroupID),
                           let transcript = defaults.string(forKey: "latestTranscript") {
                            AppState.shared.editingTranscript = transcript
                            // IMPORTANT: Still set the session ID so we can update the correct record
                            AppState.shared.editingSessionId = sessionId
                            AppState.shared.showEditView = true
                        }
                    }
                } else {
                    // No session ID in URL - legacy fallback
                    if let defaults = UserDefaults(suiteName: appGroupID),
                       let transcript = defaults.string(forKey: "latestTranscript") {
                        AppState.shared.editingTranscript = transcript
                        AppState.shared.editingSessionId = nil
                        AppState.shared.showEditView = true
                        print("[App] Editing via legacy path (no session ID)")
                    }
                }
            }
        } else if url.host == "transcribe" {
            // Triggered from keyboard - transcribe pending audio
            NotificationCenter.default.post(name: .transcribePendingAudio, object: nil)
        }
    }
}
#endif

// MARK: - Recording Coordinator (bridges floating pill and main UI)

@MainActor
class RecordingCoordinator: ObservableObject {
    static let shared = RecordingCoordinator()

    @Published var isRecording = false
    @Published var audioLevel: Float = 0
    @Published var showExpandedView = false

    private init() {}

    func updateState(isRecording: Bool, audioLevel: Float) {
        self.isRecording = isRecording
        self.audioLevel = audioLevel

        // Notify floating pill
        NotificationCenter.default.post(
            name: .recordingStateChanged,
            object: nil,
            userInfo: ["isRecording": isRecording, "audioLevel": audioLevel]
        )
    }
}

// MARK: - App State

@MainActor
class AppState: ObservableObject {
    static let shared = AppState()

    @Published var latestTranscript: String = ""
    @Published var isTranscribing: Bool = false
    @Published var showEditView: Bool = false
    @Published var editingTranscript: String = ""
    @Published var editingSessionId: String? = nil  // For database sync

    #if os(macOS)
    // Focus restoration for auto-paste
    var previousApp: NSRunningApplication?

    /// Save the currently focused app before starting recording
    func saveFocusedApp() {
        previousApp = NSWorkspace.shared.frontmostApplication
        print("📍 Saved focus: \(previousApp?.localizedName ?? "none")")
    }

    /// Restore focus to the previously focused app
    func restoreFocus() {
        guard let app = previousApp else {
            print("📍 No previous app to restore focus to")
            return
        }

        print("📍 Restoring focus to: \(app.localizedName ?? "unknown")")
        app.activate(options: [])
        previousApp = nil
    }
    #endif
}

// MARK: - Auto-Paste (macOS only)

#if os(macOS)
@MainActor
func simulatePaste() {
    let source = CGEventSource(stateID: .hidSystemState)

    // Key code 9 = 'V' key
    if let keyDown = CGEvent(keyboardEventSource: source, virtualKey: 9, keyDown: true) {
        keyDown.flags = .maskCommand
        keyDown.post(tap: .cghidEventTap)
    }

    usleep(10000) // 10ms delay

    if let keyUp = CGEvent(keyboardEventSource: source, virtualKey: 9, keyDown: false) {
        keyUp.flags = .maskCommand
        keyUp.post(tap: .cghidEventTap)
    }

    print("⌨️ Simulated Cmd+V paste")
}

/// Copy text to clipboard
func copyToClipboard(_ text: String) {
    NSPasteboard.general.clearContents()
    NSPasteboard.general.setString(text, forType: .string)
    print("📋 Copied to clipboard: \(text.prefix(50))...")
}

/// Full auto-paste flow: copy, restore focus, paste
func autoPaste(_ text: String) {
    copyToClipboard(text)

    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
        AppState.shared.restoreFocus()

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            simulatePaste()
        }
    }
}
#endif

// MARK: - App Delegate (macOS only)

#if os(macOS)
@MainActor
class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.activate(ignoringOtherApps: true)
        registerGlobalHotkeys()
    }

    nonisolated func registerGlobalHotkeys() {
        // Global hotkey: Ctrl+Shift+Space to toggle recording
        NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { event in
            Task { @MainActor in
                Self.handleGlobalKeyEvent(keyCode: event.keyCode, modifiers: event.modifierFlags)
            }
        }

        NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            Task { @MainActor in
                Self.handleGlobalKeyEvent(keyCode: event.keyCode, modifiers: event.modifierFlags)
            }
            return event
        }
    }

    static func handleGlobalKeyEvent(keyCode: UInt16, modifiers: NSEvent.ModifierFlags) {
        let hasCtrl = modifiers.contains(.control)
        let hasShift = modifiers.contains(.shift)
        let isSpace = keyCode == 49

        // Ctrl+Shift+Space - Toggle recording
        if hasCtrl && hasShift && isSpace {
            print("🎤 Hotkey triggered: Ctrl+Shift+Space")

            // Save focused app BEFORE we take focus
            AppState.shared.saveFocusedApp()

            // Toggle recording
            NotificationCenter.default.post(name: .toggleRecording, object: nil)
        }

        // Escape - Cancel recording
        if keyCode == 53 {
            NotificationCenter.default.post(name: .cancelRecording, object: nil)
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        return true
    }
}
#endif

// MARK: - Notifications

extension Notification.Name {
    static let toggleRecording = Notification.Name("toggleRecording")
    static let cancelRecording = Notification.Name("cancelRecording")
    static let transcriptionComplete = Notification.Name("transcriptionComplete")
    static let startRecordingFromShortcut = Notification.Name("startRecordingFromShortcut")
    static let expandRecorder = Notification.Name("expandRecorder")
    static let recordingStateChanged = Notification.Name("recordingStateChanged")
    static let transcribePendingAudio = Notification.Name("transcribePendingAudio")
}
