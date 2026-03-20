# BPH-002 Fix — Hotkey Dead + Overlay Not Showing
**PRD Version:** 2.0  
**Date:** 2026-03-20  
**Priority:** P0 — App is non-functional without this  
**Effort estimate:** 2–3 hours  

---

## Problem Statement

After a macOS/Xcode update, BrainPhart Voice partially broke:

- **Global hotkey (Option+Shift) is dead** — pressing it does nothing
- **Floating overlay never appears** — the pill UI never shows
- **Main window works fine** — build, history, settings all OK
- **SuperWhisper still works** — confirming this is a permissions/API issue, not a platform limitation

### Root Cause (Diagnosed)

The global `NSEvent.addGlobalMonitorForEvents` monitor for `.flagsChanged` requires **Input Monitoring** (TCC `ListenEvent`) permission. macOS resets TCC after major OS/Xcode updates. When the permission is missing:

1. `addGlobalMonitorForEvents` silently returns `nil` — no monitor installed, no error thrown
2. The hotkey never fires
3. Recording never starts
4. The overlay never shows (it only shows during active recording)
5. The error message goes to `appState.errorMessage` — which only renders inside the overlay
6. **The overlay never shows → the error is never seen → silent failure loop**

The current code in `AppDelegate.checkPermissionsOnLaunch()` already detects missing permissions and calls `CGRequestListenEventAccess()` — but:
- If the user previously denied, the system dialog doesn't re-appear
- The fallback error message goes to the overlay which is invisible
- `flagsMonitor` is never checked for `nil` after assignment

---

## Acceptance Criteria

All 5 criteria must pass before declaring this job DONE.

### AC-1: Hotkey Works Without Input Monitoring Denial

**What:** The global hotkey must fire even if Input Monitoring is denied.

**How:** Switch the hotkey registration to use Carbon's `RegisterEventHotKey` API for a modifier+key combination, OR detect that `flagsMonitor` is `nil` after `addGlobalMonitorForEvents` and surface a **persistent, unavoidable** alert — not just an overlay error.

**Preferred approach (simpler, less risky):** Detect nil monitor → fire macOS UserNotification + show NSAlert immediately at launch → direct user to System Settings > Privacy > Input Monitoring. Do NOT silently proceed.

**Test:** Deny Input Monitoring in System Settings. Relaunch app. A visible alert or notification must appear within 3 seconds of launch. The error must not require recording to be active to be seen.

---

### AC-2: Monitor Installation Is Verified

**What:** After calling `addGlobalMonitorForEvents`, check whether it returned `nil`. If nil, treat it as a hard error.

**File:** `Sources/VoiceRecorder/VoiceRecorderApp.swift` — `registerGlobalHotkey()` method

**Change:** Add nil check:
```swift
flagsMonitor = NSEvent.addGlobalMonitorForEvents(matching: .flagsChanged) { ... }

if flagsMonitor == nil {
    // Permission denied or unavailable — surface this visibly
    showPermissionBlockerAlert()
    log.error("Global hotkey monitor returned nil — Input Monitoring denied or unavailable")
}
```

**Test:** Set `flagsMonitor = nil` manually after registration (temporary test). Confirm the blocker alert fires.

---

### AC-3: Critical Errors Surface Outside the Overlay

**What:** When the app cannot function (no hotkey, no model loaded), the error must be visible WITHOUT the overlay being active.

**Options (pick one or both):**
1. **Menu bar badge** — Add a red dot or "!" to the status bar icon when a critical error exists
2. **macOS UserNotification** — Post a `UNUserNotificationCenter` notification for P0 errors (no hotkey, no model)
3. **NSAlert on launch** — For hard blockers (no hotkey), show an NSAlert immediately, not deferred

**Do NOT:** Route P0 errors only to `appState.errorMessage`. That path is invisible when the overlay is not shown.

**Test:** Trigger a known failure (deny Input Monitoring). Relaunch. A notification or alert must appear without any user action beyond launching the app.

---

### AC-4: Overlay Shows Correctly When Recording Starts

**What:** When recording IS triggered (e.g. via menu bar item or keyboard shortcut from main window), the overlay must appear.

**Current behaviour:** Overlay may not appear because `showWindow()` calls `window?.orderFrontRegardless()` but the panel may not be on the current Space if app is in accessory mode.

**Fix:** In `FloatingPanelController.showWindow()`, add:
```swift
override func showWindow(_ sender: Any?) {
    super.showWindow(sender)
    window?.orderFrontRegardless()
    // Ensure it appears on the current Space
    window?.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
}
```

Also verify that `AppState.showFloatingOverlay()` is being called when recording starts. Add a log line confirming it fires.

**Test:** Trigger recording via menu bar "Toggle Recording" item. The overlay pill must appear within 500ms on the current Space.

---

### AC-5: Zero Silent Failures — All Critical Paths Log and Surface Errors

**What:** Every critical failure must produce BOTH:
1. An `os.log` entry at `.error` level
2. A visible error surface (overlay error banner, NSAlert, or UserNotification)

**Critical paths to audit and fix:**
- `addGlobalMonitorForEvents` returns nil → currently silent
- `addGlobalMonitorForEvents` for escape key returns nil → currently silent  
- `Config.resolveModelPath()` returns nil → currently sets overlay error (OK) but also needs log at `.error`
- `WhisperBridge.loadModel()` returns false → currently sets overlay error (OK), verify log level is `.error` not `.info`
- `FloatingPanelController.showWindow()` → add log confirming panel is being ordered front

**Test:** Search codebase for any `setError(` call that does NOT have a corresponding `log.error(` call in the same function. Fix each one.

---

## Files to Modify

| File | Change |
|------|--------|
| `Sources/VoiceRecorder/VoiceRecorderApp.swift` | Nil-check after `addGlobalMonitorForEvents`; add `showPermissionBlockerAlert()`; add UserNotification for P0 errors |
| `Sources/VoiceRecorder/FloatingOverlay.swift` | Add log in `showWindow()`; ensure `collectionBehavior` is set on show |
| `Sources/VoiceRecorder/AppState.swift` | Add `setError()` wrapper that also logs at `.error` level |
| `Sources/VoiceRecorder/Config.swift` | Confirm model path failure logs at `.error` not `.info` |

---

## What NOT To Do

- Do NOT rewrite the hotkey system from scratch unless both nil-check approach and UserNotification approach fail after testing
- Do NOT remove the existing `checkPermissionsOnLaunch()` logic — extend it
- Do NOT use `print()` for error logging — use `os.log` Logger with `.error` level
- Do NOT declare done without running `swift build -c release` with zero errors
- Do NOT declare done without manually testing the overlay appears when recording is triggered from the menu bar

---

## Build & Verification Steps (Mandatory Before Declaring Done)

```bash
# Step 1: Build C++ core (only if .cpp files changed)
cmake -B build -DCMAKE_BUILD_TYPE=Release -DWHISPER_METAL=ON
cmake --build build -j

# Step 2: Build Swift app — MUST be zero errors
swift build -c release 2>&1
swift build -c release 2>&1 | grep "error:" | wc -l
# Expected: 0

# Step 3: Run and verify overlay appears via menu bar trigger
.build/release/VoiceRecorder &
# Click menu bar icon → Toggle Recording
# MUST see the pill overlay appear

# Step 4: Check logs for any silent error paths
log stream --predicate 'subsystem == "art.brainph.voice"' --level error
# Should see startup logs, no silent failures
```

---

## Definition of Done

- [ ] `swift build -c release` → 0 errors
- [ ] `flagsMonitor` nil-check implemented — logs at `.error` if nil
- [ ] P0 error (no hotkey) surfaces as NSAlert or UserNotification without overlay being active
- [ ] Overlay appears when recording triggered via menu bar item
- [ ] All `setError()` calls have corresponding `log.error()` in same function
- [ ] No new features added — scope is fix only

---

## Context for Agent

- Project path: `/Users/kjd/01-projects/BPH-002-brainphart-voice-recorder`
- Build: `swift build -c release` (Swift-only rebuild if only .swift files changed)
- The C++ core, whisper.cpp, and FFmpeg are all working — do NOT touch them
- The main window, history, settings are all working — do NOT touch them
- The recording pipeline itself works — only the hotkey trigger and overlay display are broken
- Read `CLAUDE.md` before touching any file
- Read the source file you are editing BEFORE making changes
- Do NOT edit any file more than 5 times without running `swift build` to verify
