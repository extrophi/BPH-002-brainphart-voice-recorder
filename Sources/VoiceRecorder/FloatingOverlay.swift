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

        panel.contentViewController = hostingView

        // Size the panel to fit the SwiftUI content.
        panel.setContentSize(NSSize(width: 280, height: 56))
        panel.center()

        // Nudge to upper-right quadrant of the screen.
        if let screen = NSScreen.main {
            let screenFrame = screen.visibleFrame
            let x = screenFrame.maxX - 300
            let y = screenFrame.maxY - 100
            panel.setFrameOrigin(NSPoint(x: x, y: y))
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
            styleMask: [.borderless, .nonactivatingPanel, .hudWindow],
            backing: .buffered,
            defer: false
        )

        // Float above everything.
        level = .floating
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]

        // Transparent / rounded appearance.
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true

        // Allow the panel to become key only when the user clicks a control
        // inside it.
        becomesKeyOnlyIfNeeded = true

        // Keep on screen across space changes.
        hidesOnDeactivate = false

        // Allow dragging.
        isMovableByWindowBackground = true
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
        .background(.ultraThinMaterial, in: Capsule())
        .shadow(color: .black.opacity(0.25), radius: 8, y: 4)
        .fixedSize()
        // Animate layout transitions smoothly.
        .animation(.easeInOut(duration: 0.25), value: appState.isRecording)
        .animation(.easeInOut(duration: 0.25), value: appState.isTranscribing)
    }

    // MARK: - Idle

    private var idleView: some View {
        HStack(spacing: 8) {
            Image(systemName: "mic.fill")
                .foregroundStyle(.secondary)
                .font(.system(size: 14, weight: .medium))

            Text("Ready")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.secondary)

            Text("Cmd+Shift+Space")
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

            // Mini waveform.
            WaveformView(
                samples: appState.meteringSamples,
                barColor: .green,
                barCount: 24
            )
            .frame(width: 100, height: 28)

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
