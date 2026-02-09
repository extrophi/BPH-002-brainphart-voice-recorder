# NSPanel Floating Windows Reference (Fetched: 2026-02-09)

**Target macOS:** 10.13+ (NSPanel available since macOS 10.0)
**Relevant APIs:** AppKit, NSPanel, NSWindow, NSHostingView

---

## Overview

NSPanel is an NSWindow subclass optimized for auxiliary, always-on-top floating windows. Unlike NSWindow, panels:
- Float above other application windows (including main windows)
- Receive keyboard input without becoming the main window
- Disappear when the app becomes inactive (by default)
- Don't appear in the Window menu

Perfect for floating palettes, transcription overlays, status displays, and control panels.

---

## Window Levels

Configure stacking order via `window.level`:

| Level | Value | Usage |
|-------|-------|-------|
| `.floating` | 3 | Default for most floating panels (above normal windows) |
| `.statusBar` | 25 | Above floating windows (menu bar level) |
| `.popUpMenu` | 101 | Above status bar |
| `.screenSaver` | 16384 | Screensaver level |

**Note:** Higher values appear above lower values.

```swift
panel.level = .floating  // Typical for transcription overlay
```

---

## Collection Behavior Flags

Set via `window.collectionBehavior.insert(_:)` or assignment:

### Spaces Behavior
- `.canJoinAllSpaces` — Panel appears on all spaces (like menu bar)
- `.moveToActiveSpace` — Panel follows active space
- (default) — Panel tied to single space

### Exposé/Mission Control Behavior
- `.stationary` — Panel unaffected by Exposé (stays visible) — **recommended for floating UI**
- `.transient` — Floats in Spaces, hidden in Exposé (default for non-normal levels)
- `.managed` — Participates in Spaces/Exposé

### Window Cycling
- `.ignoresCycle` — Excluded from Cmd+` window cycling
- `.participatesInCycle` — Included in cycling

### Full Screen
- `.fullScreenAuxiliary` — Panel visible over full-screen apps (essential for persistent overlays)

**Recommended configuration:**

```swift
panel.collectionBehavior = [
    .canJoinAllSpaces,        // Visible on all spaces
    .stationary,              // Not hidden by Exposé
    .fullScreenAuxiliary,     // Visible over full-screen apps
    .ignoresCycle             // Exclude from Cmd+`
]
```

---

## Activation & Focus Control

### `hidesOnDeactivate`
**Boolean** — Hide panel when app loses focus.

```swift
panel.hidesOnDeactivate = false  // Keep visible when app inactive (for always-on-top)
```

- `true` (default) — Panel hidden when app becomes inactive
- `false` — Panel remains visible and clickable even if app is inactive

### `becomesKeyOnlyIfNeeded`
**Boolean** — Panel becomes key window only when user clicks inside it.

```swift
panel.becomesKeyOnlyIfNeeded = true  // Don't steal focus on open
```

- `true` — Panel doesn't automatically become key; user must click to activate
- `false` (default) — Panel becomes key window immediately

### Style Mask: `.nonactivatingPanel`
Prevents app activation when panel opens:

```swift
panel.styleMask.insert(.nonactivatingPanel)
// Or at initialization:
let panel = NSPanel(contentRect: rect, styleMask: .nonactivatingPanel, backing: .buffered, defer: false)
```

---

## Transparent & Borderless Setup

```swift
let panel = NSPanel(contentRect: frame, styleMask: .nonactivatingPanel, backing: .buffered, defer: false)

// Remove window chrome
panel.styleMask.remove(.titled)
panel.styleMask.remove(.closable)
panel.styleMask.remove(.miniaturizable)
panel.styleMask.remove(.resizable)

// Transparency
panel.isOpaque = false
panel.backgroundColor = NSColor.clear

// Allow dragging by background
panel.isMovableByWindowBackground = true
```

---

## SwiftUI Integration with NSHostingController

### Basic Pattern

```swift
import SwiftUI
import AppKit

class FloatingPanelController {
    static let shared = FloatingPanelController()
    var panel: NSPanel?

    func show<Content: View>(_ content: Content) {
        let frame = NSRect(x: 100, y: 100, width: 400, height: 300)
        let panel = NSPanel(contentRect: frame, styleMask: .nonactivatingPanel, backing: .buffered, defer: false)

        // Configure panel
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary]
        panel.hidesOnDeactivate = false
        panel.becomesKeyOnlyIfNeeded = true
        panel.isMovableByWindowBackground = true
        panel.isOpaque = false
        panel.backgroundColor = NSColor.clear

        // Host SwiftUI content
        let hostingView = NSHostingView(rootView: content)
        panel.contentView = hostingView

        panel.makeKeyAndOrderFront(nil)
        self.panel = panel
    }
}
```

### AppDelegate Setup

```swift
import AppKit
import SwiftUI

@main
struct MyApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}

class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        // Create floating panel on app launch
        FloatingPanelController.shared.show(
            TranscriptionOverlay()
        )
    }
}
```

### SwiftUI View for Panel Content

```swift
struct TranscriptionOverlay: View {
    @State private var transcript = ""

    var body: some View {
        VStack(spacing: 12) {
            Text("Transcription")
                .font(.headline)

            TextEditor(text: $transcript)
                .frame(minHeight: 100)
                .padding()

            HStack {
                Button("Clear") { transcript = "" }
                Button("Copy") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(transcript, forType: .string)
                }
            }
            .padding()
        }
        .padding()
        .background(Color(nsColor: NSColor.controlBackgroundColor))
    }
}
```

---

## Key Properties Summary

| Property | Type | Purpose | Typical Value |
|----------|------|---------|----------------|
| `level` | `NSWindow.Level` | Window stacking order | `.floating` |
| `collectionBehavior` | `Set<NSWindow.CollectionBehavior>` | Spaces/Exposé behavior | `[.canJoinAllSpaces, .stationary, .fullScreenAuxiliary]` |
| `hidesOnDeactivate` | `Bool` | Hide when app inactive | `false` (for persistent overlay) |
| `becomesKeyOnlyIfNeeded` | `Bool` | Non-activating panel | `true` |
| `isMovableByWindowBackground` | `Bool` | Drag window by background | `true` |
| `styleMask` | `NSWindow.StyleMask` | Window chrome | `.nonactivatingPanel` |
| `isOpaque` | `Bool` | Transparency support | `false` |
| `backgroundColor` | `NSColor` | Background color | `NSColor.clear` |

---

## Complete Working Example

```swift
import AppKit
import SwiftUI

class TranscriptionPanel: NSPanel {
    init(frame: NSRect) {
        super.init(contentRect: frame, styleMask: .nonactivatingPanel, backing: .buffered, defer: false)

        // Window level & behavior
        self.level = .floating
        self.collectionBehavior = [
            .canJoinAllSpaces,
            .stationary,
            .fullScreenAuxiliary,
            .ignoresCycle
        ]

        // Focus control
        self.hidesOnDeactivate = false
        self.becomesKeyOnlyIfNeeded = true

        // Appearance
        self.isOpaque = false
        self.backgroundColor = NSColor(white: 0.95, alpha: 0.95)
        self.isMovableByWindowBackground = true

        // Host SwiftUI content
        let content = NSHostingView(rootView: PanelContentView())
        self.contentView = content
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}

struct PanelContentView: View {
    @State var isRecording = false

    var body: some View {
        VStack(spacing: 16) {
            HStack {
                Circle()
                    .fill(isRecording ? Color.red : Color.gray)
                    .frame(width: 12, height: 12)
                Text(isRecording ? "Recording..." : "Ready")
                Spacer()
            }
            .padding(.horizontal)

            Button(action: { isRecording.toggle() }) {
                Text(isRecording ? "Stop" : "Start")
                    .frame(maxWidth: .infinity)
            }
            .padding()
        }
        .padding()
        .frame(width: 300, height: 120)
    }
}
```

---

## Common Pitfalls

1. **Panel disappears when app loses focus** — Set `hidesOnDeactivate = false`
2. **Panel steals focus on creation** — Add `.nonactivatingPanel` to styleMask or set `becomesKeyOnlyIfNeeded = true`
3. **Panel hidden in full-screen apps** — Add `.fullScreenAuxiliary` to collectionBehavior
4. **Panel hidden by Exposé** — Add `.stationary` to collectionBehavior
5. **Can't drag panel by background** — Set `isMovableByWindowBackground = true`
6. **Transparency not working** — Set `isOpaque = false` and `backgroundColor = NSColor.clear`

---

## Sources

- [NSPanel - Apple Developer Documentation](https://developer.apple.com/documentation/appkit/nspanel)
- [Setting Window Collection Behavior](https://developer.apple.com/library/archive/documentation/Cocoa/Conceptual/WinPanel/Articles/SettingWindowCollectionBehavior.html)
- [hidesOnDeactivate - Apple Documentation](https://developer.apple.com/documentation/appkit/nswindow/1419777-hidesondeactivate)
- [becomesKeyOnlyIfNeeded - Apple Documentation](https://developer.apple.com/documentation/appkit/nspanel/becomeskeyonlyifneeded)
- [Create a Spotlight/Alfred-like Window on macOS with SwiftUI](https://www.markusbodner.com/til/2021/02/08/create-a-spotlight/alfred-like-window-on-macos-with-swiftui/)
- [Make a Floating Panel in SwiftUI for macOS](https://cindori.com/developer/floating-panel)
