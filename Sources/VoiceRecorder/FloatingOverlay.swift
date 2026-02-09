//
//  FloatingOverlay.swift
//  VoiceRecorder
//
//  NSPanel-based floating window that stays above all other windows.
//
//  Layout:
//  - Idle:          Compact pill — mic icon + "Ready"
//  - Recording:     Expanded pill — waveform + elapsed timer + stop button
//  - Transcribing:  Progress bar + percentage
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
           defaults.object(forKey: "pillPositionY") != nil {
            let x = defaults.double(forKey: "pillPositionX")
            let y = defaults.double(forKey: "pillPositionY")
            panel.setFrameOrigin(NSPoint(x: x, y: y))
        } else if let screen = NSScreen.main {
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
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]

        // Fully transparent — no window chrome, no border, no outline.
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false

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

            // Main pill content.
            Group {
                if appState.isTranscribing {
                    transcribingView
                } else if appState.isRecording {
                    recordingView
                } else {
                    idleView
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
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

    // MARK: - Idle

    private var idleView: some View {
        HStack(spacing: 8) {
            Image(systemName: "mic.fill")
                .foregroundStyle(.secondary)
                .font(.system(size: 14, weight: .medium))

            VStack(alignment: .leading, spacing: 1) {
                Text("BrainPhart Voice")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.secondary)
                Text("Local privacy-first voice transcriber")
                    .font(.system(size: 9, weight: .regular))
                    .foregroundStyle(.tertiary)
            }

            Text("⌥⇧R")
                .font(.system(size: 10, weight: .regular, design: .monospaced))
                .foregroundStyle(.tertiary)
        }
    }

    // MARK: - Recording

    private var recordingView: some View {
        HStack(spacing: 10) {
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
            .frame(width: 120, height: 28)

            // Elapsed time.
            Text(formattedElapsed)
                .font(.system(size: 13, weight: .medium, design: .monospaced))
                .foregroundStyle(.primary)
                .monospacedDigit()

            // Stop button.
            Button {
                appState.stopRecording()
            } label: {
                Image(systemName: "stop.fill")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 26, height: 26)
                    .background(.red, in: Circle())
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: - Transcribing

    private var transcribingView: some View {
        HStack(spacing: 10) {
            ProgressView(value: Double(appState.transcriptionProgress))
                .progressViewStyle(.linear)
                .frame(width: 140)
                .tint(.orange)

            Text("\(Int(appState.transcriptionProgress * 100))%")
                .font(.system(size: 12, weight: .medium, design: .monospaced))
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
