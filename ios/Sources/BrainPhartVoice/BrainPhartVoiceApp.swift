import SwiftUI

// MARK: - App Entry Point

@main
struct BrainPhartVoiceApp: App {
    #if os(macOS)
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    #endif

    @StateObject private var appState = AppState.shared

    var body: some Scene {
        #if os(macOS)
        // Main window (hidden by default, shown for full mode)
        WindowGroup {
            ContentView()
                .environmentObject(appState)
                .frame(minWidth: 800, minHeight: 500)
        }
        .windowStyle(.hiddenTitleBar)
        .commands {
            CommandGroup(replacing: .newItem) {}
            CommandMenu("Recording") {
                Button("Toggle Recording") {
                    NotificationCenter.default.post(name: .toggleRecording, object: nil)
                }
                .keyboardShortcut("r", modifiers: [.control, .shift])

                Button("Cancel Recording") {
                    NotificationCenter.default.post(name: .cancelRecording, object: nil)
                }
                .keyboardShortcut(.escape, modifiers: [])
            }
            CommandMenu("Window") {
                Button("Micro Mode") {
                    appState.windowMode = .micro
                }
                .keyboardShortcut("1", modifiers: [.command])

                Button("Medium Mode") {
                    appState.windowMode = .medium
                }
                .keyboardShortcut("2", modifiers: [.command])

                Button("Full Mode") {
                    appState.windowMode = .full
                }
                .keyboardShortcut("3", modifiers: [.command])
            }
        }

        // Settings window
        Settings {
            SettingsView()
                .environmentObject(appState)
        }
        #else
        // iOS: Simple window group
        WindowGroup {
            ContentView()
                .environmentObject(appState)
        }
        #endif
    }
}

// MARK: - App State

@MainActor
final class AppState: ObservableObject {
    static let shared = AppState()

    @Published var windowMode: WindowMode = .medium {
        didSet {
            #if os(macOS)
            updateWindowMode()
            #endif
        }
    }

    @Published var isRecording = false
    @Published var selectedSessionId: String?

    // Store the previous app for focus restoration
    private var previousApp: Any?

    private init() {}

    #if os(macOS)
    func saveFocus() {
        previousApp = NSWorkspace.shared.frontmostApplication
    }

    func restoreFocus() {
        if let app = previousApp as? NSRunningApplication {
            app.activate(options: .activateIgnoringOtherApps)
        }
    }

    private func updateWindowMode() {
        guard let delegate = NSApp.delegate as? AppDelegate else { return }

        switch windowMode {
        case .micro:
            delegate.showMicroPanel()
        case .medium:
            delegate.showMediumPanel()
        case .full:
            delegate.showFullWindow()
        }
    }
    #endif
}

// MARK: - Window Mode

enum WindowMode: String, CaseIterable {
    case micro = "Micro"
    case medium = "Medium"
    case full = "Full"
}

// MARK: - Notification Names

extension Notification.Name {
    static let toggleRecording = Notification.Name("toggleRecording")
    static let cancelRecording = Notification.Name("cancelRecording")
    static let openSettings = Notification.Name("openSettings")
    static let transcriptionComplete = Notification.Name("transcriptionComplete")
    static let transcriptSaved = Notification.Name("transcriptSaved")
}

// MARK: - macOS App Delegate

#if os(macOS)
import AppKit

@MainActor
class AppDelegate: NSObject, NSApplicationDelegate {
    var floatingPanel: FloatingPanel?
    var microPanel: FloatingPanel?
    private var eventMonitor: Any?

    nonisolated func applicationDidFinishLaunching(_ notification: Notification) {
        Task { @MainActor in
            // Create floating panels
            setupPanels()

            // Register global hotkey
            setupGlobalHotkey()

            // Start in medium mode
            showMediumPanel()

            // Start transcription worker
            Task {
                await TranscriptionWorker.shared.start()
            }

            print("BrainPhartVoice launched")
        }
    }

    nonisolated func applicationWillTerminate(_ notification: Notification) {
        Task { @MainActor in
            if let monitor = self.eventMonitor {
                NSEvent.removeMonitor(monitor)
            }
        }
    }

    private func setupPanels() {
        // Medium panel (floating recorder)
        floatingPanel = FloatingPanel(
            contentRect: NSRect(x: 0, y: 0, width: 320, height: 120),
            showsTitleBar: false
        )
        floatingPanel?.contentView = NSHostingView(rootView:
            ContentView()
                .environmentObject(AppState.shared)
        )

        // Micro panel (pill)
        microPanel = FloatingPanel(
            contentRect: NSRect(x: 0, y: 0, width: 200, height: 48),
            showsTitleBar: false
        )
        microPanel?.contentView = NSHostingView(rootView:
            ContentView()
                .environmentObject(AppState.shared)
        )
    }

    private func setupGlobalHotkey() {
        // Ctrl+Shift+Space to toggle recording
        eventMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
            if event.modifierFlags.contains([.control, .shift]) && event.keyCode == 49 { // Space
                Task { @MainActor in
                    AppState.shared.saveFocus()
                    NotificationCenter.default.post(name: .toggleRecording, object: nil)
                    self?.showMediumPanel()
                }
            }
        }
    }

    func showMicroPanel() {
        floatingPanel?.orderOut(nil)
        NSApp.windows.filter { !($0 is FloatingPanel) }.forEach { $0.orderOut(nil) }

        // Position at top center of screen
        if let screen = NSScreen.main {
            let screenFrame = screen.visibleFrame
            let x = screenFrame.midX - 100
            let y = screenFrame.maxY - 80
            microPanel?.setFrame(NSRect(x: x, y: y, width: 200, height: 48), display: true)
        }

        microPanel?.makeKeyAndOrderFront(nil)
    }

    func showMediumPanel() {
        microPanel?.orderOut(nil)
        NSApp.windows.filter { !($0 is FloatingPanel) }.forEach { $0.orderOut(nil) }

        // Position at top center of screen
        if let screen = NSScreen.main {
            let screenFrame = screen.visibleFrame
            let x = screenFrame.midX - 160
            let y = screenFrame.maxY - 160
            floatingPanel?.setFrame(NSRect(x: x, y: y, width: 320, height: 120), display: true)
        }

        floatingPanel?.makeKeyAndOrderFront(nil)
    }

    func showFullWindow() {
        floatingPanel?.orderOut(nil)
        microPanel?.orderOut(nil)

        // Show main window
        if let window = NSApp.windows.first(where: { !($0 is FloatingPanel) }) {
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
        }
    }
}
#endif
