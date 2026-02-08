//
//  AutoPaste.swift
//  VoiceRecorder
//
//  Pastes transcribed text at the user's current cursor location by:
//  1. Copying the text to NSPasteboard (system clipboard).
//  2. Simulating a Cmd+V keystroke via CGEvent.
//
//  Requires the Accessibility permission (System Settings > Privacy &
//  Security > Accessibility).  If the permission has not been granted,
//  an alert is shown directing the user to the correct settings pane.
//

import AppKit
import ApplicationServices

enum AutoPaste {

    // MARK: - Public API

    /// Paste `text` at the current cursor position in whatever app is frontmost.
    ///
    /// The method is safe to call from any context; it will check for
    /// Accessibility permission first and show an alert if needed.
    @MainActor
    static func pasteText(_ text: String) {
        guard !text.isEmpty else { return }

        // 1. Check accessibility permission.
        guard ensureAccessibilityPermission() else { return }

        // 2. Write text to the system pasteboard.
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)

        // 3. Brief delay to let the pasteboard write settle, then simulate
        //    Cmd+V in the frontmost application.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            simulatePaste()
        }
    }

    // MARK: - Accessibility Check

    /// Returns `true` if the process is trusted for Accessibility.
    /// On first call (when not yet trusted) macOS may show its own prompt;
    /// we also display an explanatory alert.
    @MainActor
    static func ensureAccessibilityPermission() -> Bool {
        let options = [kAXTrustedCheckOptionPrompt.takeRetainedValue(): true] as CFDictionary
        let trusted = AXIsProcessTrustedWithOptions(options)

        if !trusted {
            showAccessibilityAlert()
        }
        return trusted
    }

    // MARK: - Simulate Cmd+V

    /// Uses CGEvent to post a Cmd+V keystroke to the system event stream.
    private static func simulatePaste() {
        // Virtual keycode for "V" is 9.
        let keyCodeV: CGKeyCode = 9

        let source = CGEventSource(stateID: .hidSystemState)

        // Key down with Cmd flag.
        guard let keyDown = CGEvent(keyboardEventSource: source,
                                    virtualKey: keyCodeV,
                                    keyDown: true) else { return }
        keyDown.flags = .maskCommand

        // Key up with Cmd flag.
        guard let keyUp = CGEvent(keyboardEventSource: source,
                                  virtualKey: keyCodeV,
                                  keyDown: false) else { return }
        keyUp.flags = .maskCommand

        // Post to the HID event tap so the frontmost app receives the events.
        keyDown.post(tap: .cghidEventTap)
        keyUp.post(tap: .cghidEventTap)
    }

    // MARK: - Alert

    @MainActor
    private static func showAccessibilityAlert() {
        let alert = NSAlert()
        alert.messageText = "Accessibility Permission Required"
        alert.informativeText = """
            Voice Recorder needs Accessibility permission to auto-paste \
            transcriptions at your cursor.

            Please grant access in:
            System Settings > Privacy & Security > Accessibility

            Then relaunch the app.
            """
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Open System Settings")
        alert.addButton(withTitle: "Cancel")

        let response = alert.runModal()
        if response == .alertFirstButtonReturn {
            openAccessibilitySettings()
        }
    }

    /// Opens the macOS Accessibility privacy pane.
    private static func openAccessibilitySettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }
}
