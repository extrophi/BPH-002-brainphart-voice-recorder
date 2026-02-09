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

        let pasteboard = NSPasteboard.general

        // 1. Save the user's current clipboard contents (all types).
        let savedItems = saveClipboard(pasteboard)

        // 2. Copy transcription to clipboard.
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)

        // 3. Try to auto-paste via Cmd+V if accessibility is granted.
        //    If not granted, the text is still on the clipboard for manual paste
        //    — don't restore in that case, the user needs the text available.
        guard ensureAccessibilityPermission() else { return }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            simulatePaste()

            // 4. Restore original clipboard after the paste event is processed.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                restoreClipboard(savedItems, to: pasteboard)
            }
        }
    }

    // MARK: - Clipboard Save / Restore

    /// Snapshot of a single pasteboard item: an ordered list of (type, data) pairs.
    private typealias ItemSnapshot = [(NSPasteboard.PasteboardType, Data)]

    /// Saves all items currently on the pasteboard as raw data.
    /// Returns an empty array if the clipboard is empty.
    private static func saveClipboard(_ pasteboard: NSPasteboard) -> [ItemSnapshot] {
        guard let items = pasteboard.pasteboardItems else { return [] }
        var snapshots: [ItemSnapshot] = []
        for item in items {
            var pairs: ItemSnapshot = []
            for type in item.types {
                if let data = item.data(forType: type) {
                    pairs.append((type, data))
                }
            }
            if !pairs.isEmpty {
                snapshots.append(pairs)
            }
        }
        return snapshots
    }

    /// Restores previously saved clipboard contents.
    /// If `snapshots` is empty, clears the pasteboard (there was nothing to restore).
    private static func restoreClipboard(_ snapshots: [ItemSnapshot], to pasteboard: NSPasteboard) {
        pasteboard.clearContents()
        guard !snapshots.isEmpty else { return }
        var pbItems: [NSPasteboardItem] = []
        for snapshot in snapshots {
            let item = NSPasteboardItem()
            for (type, data) in snapshot {
                item.setData(data, forType: type)
            }
            pbItems.append(item)
        }
        pasteboard.writeObjects(pbItems)
    }

    // MARK: - Accessibility Check

    /// Whether we've already shown the accessibility alert this launch.
    private static var hasShownAlert = false

    /// Returns `true` if the process is trusted for Accessibility.
    /// Shows an explanatory alert at most once per app launch if not trusted.
    @MainActor
    static func ensureAccessibilityPermission() -> Bool {
        let trusted = AXIsProcessTrusted()

        if !trusted && !hasShownAlert {
            hasShownAlert = true
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
            BrainPhart Voice needs Accessibility permission to auto-paste \
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
