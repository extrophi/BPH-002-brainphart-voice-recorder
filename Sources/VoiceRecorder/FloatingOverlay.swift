//
//  FloatingOverlay.swift
//  VoiceRecorder
//
//  NSPanel-based floating window that stays above all other windows.
//
//  Layout (overlay only appears during recording, fades after paste):
//  - Recording:     Red dot + waveform + elapsed timer + stop button
//  - Transcribing:  Progress bar + percentage
//  - Done:          Checkmark + "Pasted" (shown briefly before fade-out)
//  - Error:         Red banner shown briefly when something fails
//
//  The panel is non-activating so it never steals focus from the frontmost app.
//  Draggable by its background.
//

import SwiftUI
import AppKit

// MARK: - FloatingPanelController

/// Manages the lifecycle of the floating NSPanel and hosts SwiftUI content
/// inside it via NSHostingController.
@MainActor
final class FloatingPanelController: NSWindowController {

    // MARK: - Init

    convenience init(appState: AppState) {
        let panel = FloatingPanel()
        self.init(window: panel)

        let hostingView = NSHostingController(
            rootView: FloatingOverlayContent()
                .environment(appState)
        )

        // Use a fixed transparent panel — the SwiftUI Capsule inside handles
        // its own sizing via .fixedSize(). Do NOT use .preferredContentSize
        // here — it causes infinite layout recursion (NSHostingView resizes
        // panel → windowDidLayout → recalculate → resize → crash).
        hostingView.sizingOptions = []

        // Make the hosting view fully transparent — no default background
        // that would show as black lines around the capsule shape.
        hostingView.view.wantsLayer = true
        hostingView.view.layer?.backgroundColor = .clear

        panel.contentViewController = hostingView

        // Large enough for all states (idle/recording/transcribing/error).
        panel.setContentSize(NSSize(width: 420, height: 100))

        // Restore saved position or default to upper-right quadrant.
        let defaults = UserDefaults.standard
        if defaults.object(forKey: "pillPositionX") != nil,
           defaults.object(forKey: "pillPositionY") != nil,
           let validOrigin = FloatingPanelController.validatedOrigin(
               NSPoint(x: defaults.double(forKey: "pillPositionX"),
                       y: defaults.double(forKey: "pillPositionY")),
               panelSize: panel.frame.size
           ) {
            panel.setFrameOrigin(validOrigin)
        } else if let screen = NSScreen.main {
            // Clear stale off-screen coordinates so next launch starts fresh
            defaults.removeObject(forKey: "pillPositionX")
            defaults.removeObject(forKey: "pillPositionY")
            let screenFrame = screen.visibleFrame
            let x = screenFrame.maxX - 300
            let y = screenFrame.maxY - 100
            panel.setFrameOrigin(NSPoint(x: x, y: y))
        }

        // Persist position whenever the panel is dragged.
        NotificationCenter.default.addObserver(
            forName: NSWindow.didMoveNotification,
            object: panel,
            queue: .main
        ) { notification in
            guard let window = notification.object as? NSWindow else { return }
            let origin = window.frame.origin
            UserDefaults.standard.set(origin.x, forKey: "pillPositionX")
            UserDefaults.standard.set(origin.y, forKey: "pillPositionY")
        }
    }

    // MARK: - Bounds Check

    /// Validate that a saved origin is visible on at least one connected screen.
    /// Returns the origin if valid, nil if off-screen.
    private static func validatedOrigin(_ origin: NSPoint, panelSize: NSSize) -> NSPoint? {
        let panelRect = NSRect(origin: origin, size: panelSize)
        for screen in NSScreen.screens {
            if screen.visibleFrame.intersects(panelRect) {
                return origin
            }
        }
        return nil
    }

    // MARK: - Show

    override func showWindow(_ sender: Any?) {
        super.showWindow(sender)
        window?.orderFrontRegardless()
    }
}

// MARK: - FloatingPanel (NSPanel subclass)

/// Custom NSPanel configured for always-on-top, non-activating, borderless
/// floating behaviour.
private final class FloatingPanel: NSPanel {

    init() {
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: 280, height: 56),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        // Float above everything.
        level = .floating
        // NOTE: .stationary was removed — it conflicts with .canJoinAllSpaces
        // on macOS 15+ and can cause the panel to not appear on the active space.
        // .ignoresCycle prevents the panel from appearing in Cmd+Tab / Window menu.
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]

        // Fully transparent — no window chrome, no border, no outline.
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false

        // Prevent the panel from being deallocated when closed — we reuse it.
        isReleasedWhenClosed = false

        // Allow the panel to become key only when the user clicks a control
        // inside it.
        becomesKeyOnlyIfNeeded = true

        // Keep on screen when app deactivates — critical for a floating overlay.
        hidesOnDeactivate = false

        // Allow dragging.
        isMovableByWindowBackground = true

        // Resize animation style.
        animationBehavior = .utilityWindow
    }

    // Allow the panel to resign key when the user clicks elsewhere.
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

// MARK: - SwiftUI Content

/// The SwiftUI view rendered inside the floating panel.
/// Adapts its layout depending on the current app state.
struct FloatingOverlayContent: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        VStack(spacing: 6) {
            // Error banner (shown above the pill when an error exists).
            if let error = appState.errorMessage {
                errorBanner(error)
            }

            // Main pill content — only visible during recording or transcribing.
            Group {
                if appState.isTranscribing {
                    transcribingView
                } else if appState.isRecording {
                    recordingView
                } else {
                    // Post-transcription: brief "Done" indicator before fade-out.
                    doneView
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background {
                if #available(macOS 26, *) {
                    Capsule()
                        .glassEffect(.regular.interactive(), in: .capsule)
                } else {
                    Capsule()
                        .fill(.ultraThinMaterial)
                }
            }
            .overlay {
                if appState.isRecording {
                    Capsule()
                        .strokeBorder(.red.opacity(0.6), lineWidth: 2)
                        .blur(radius: 8)
                        .modifier(PulsingModifier())
                }
            }
            .fixedSize()
        }
        // Animate layout transitions smoothly.
        .animation(.easeInOut(duration: 0.25), value: appState.isRecording)
        .animation(.easeInOut(duration: 0.25), value: appState.isTranscribing)
        .animation(.easeInOut(duration: 0.25), value: appState.errorMessage)
    }

    // MARK: - Error Banner

    private func errorBanner(_ message: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.white)
                .font(.system(size: 11))

            Text(message)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.white)
                .lineLimit(2)
                .truncationMode(.tail)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(.red.opacity(0.85), in: Capsule())
        .fixedSize()
        .onTapGesture {
            appState.dismissError()
        }
        .transition(.opacity.combined(with: .move(edge: .top)))
    }

    // MARK: - Done (shown briefly after transcription before fade-out)

    private var doneView: some View {
        HStack(spacing: 6) {
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(.green)
                .font(.system(size: 12, weight: .medium))

            Text("Pasted")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Recording

    private var recordingView: some View {
        HStack(spacing: 8) {
            // Pulsing red dot.
            Circle()
                .fill(.red)
                .frame(width: 8, height: 8)
                .modifier(PulsingModifier())

            // Mini waveform — thin dense bars.
            WaveformView.compact(
                samples: appState.meteringSamples,
                color: .green
            )
            .frame(width: 100, height: 24)

            // Elapsed time.
            Text(formattedElapsed)
                .font(.system(size: 12, weight: .medium, design: .monospaced))
                .foregroundStyle(.primary)
                .monospacedDigit()

            // Stop button.
            Button {
                appState.stopRecording()
            } label: {
                Image(systemName: "stop.fill")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 22, height: 22)
                    .background(.red, in: Circle())
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: - Transcribing

    private var transcribingView: some View {
        HStack(spacing: 8) {
            ProgressView(value: Double(appState.transcriptionProgress))
                .progressViewStyle(.linear)
                .frame(width: 120)
                .tint(.orange)

            Text("\(Int(appState.transcriptionProgress * 100))%")
                .font(.system(size: 11, weight: .medium, design: .monospaced))
                .foregroundStyle(.orange)
                .monospacedDigit()
        }
    }

    // MARK: - Helpers

    private var formattedElapsed: String {
        let mins = appState.recordingElapsedSeconds / 60
        let secs = appState.recordingElapsedSeconds % 60
        return String(format: "%d:%02d", mins, secs)
    }
}

// MARK: - BrainPhart Logo

/// Loads and displays the brainphart brain icon from bundled resources.
private struct BrainPhartLogo: View {
    var body: some View {
        if let url = Bundle.module.url(forResource: "brainph-icon", withExtension: "png"),
           let nsImage = NSImage(contentsOf: url) {
            Image(nsImage: nsImage)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .clipShape(Circle())
        } else {
            // Fallback: brain emoji as system symbol.
            Image(systemName: "brain.head.profile")
                .resizable()
                .aspectRatio(contentMode: .fit)
                .foregroundStyle(.pink)
        }
    }
}

// MARK: - Pulsing Modifier

/// Animates an opacity pulse for the red recording indicator.
private struct PulsingModifier: ViewModifier {
    @State private var isPulsing = false

    func body(content: Content) -> some View {
        content
            .opacity(isPulsing ? 0.3 : 1.0)
            .onAppear {
                withAnimation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true)) {
                    isPulsing = true
                }
            }
    }
}
