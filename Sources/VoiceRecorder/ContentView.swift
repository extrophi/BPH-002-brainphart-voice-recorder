//
//  ContentView.swift
//  VoiceRecorder
//
//  Main window content for the history/control window.
//
//  Layout:
//  - NavigationSplitView with a sidebar showing session list and a detail
//    pane showing the selected session's full transcript.
//  - Toolbar with a Record/Stop button and a Refresh button.
//  - An optional "Now" tab overlaid when a recording or transcription is
//    in progress.
//

import SwiftUI
import VoiceRecorderBridge

struct ContentView: View {
    @Environment(AppState.self) private var appState

    /// The currently selected session id in the sidebar.
    @State private var selectedSessionId: String?

    /// Whether the "Now" overlay is shown.
    @State private var showNowOverlay = false

    var body: some View {
        NavigationSplitView {
            sidebarContent
        } detail: {
            detailContent
        }
        .toolbar {
            toolbarContent
        }
        .frame(minWidth: 600, minHeight: 400)
        .overlay {
            if showNowOverlay {
                nowOverlay
            }
        }
        .onChange(of: appState.isRecording) { _, isRecording in
            if isRecording {
                showNowOverlay = true
            }
        }
        .onChange(of: appState.isTranscribing) { _, isTranscribing in
            if !isTranscribing && !appState.isRecording {
                showNowOverlay = false
            }
        }
    }

    // MARK: - Sidebar

    private var sidebarContent: some View {
        HistoryView()
            .navigationSplitViewColumnWidth(min: 280, ideal: 320)
    }

    // MARK: - Detail

    @ViewBuilder
    private var detailContent: some View {
        if let sessionId = selectedSessionId,
           let session = appState.sessions.first(where: { $0.sessionId == sessionId }) {
            SessionDetailView(session: session)
        } else {
            VStack(spacing: 12) {
                Image(systemName: "waveform")
                    .font(.system(size: 48))
                    .foregroundStyle(.tertiary)
                Text("Select a recording to view details")
                    .font(.headline)
                    .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: - Toolbar

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItemGroup(placement: .primaryAction) {
            Button {
                appState.toggleRecording()
            } label: {
                Label(
                    appState.isRecording ? "Stop" : "Record",
                    systemImage: appState.isRecording ? "stop.circle.fill" : "record.circle"
                )
            }
            .tint(appState.isRecording ? .red : .accentColor)
            .keyboardShortcut("r", modifiers: [.command])

            Button {
                appState.loadSessions()
            } label: {
                Label("Refresh", systemImage: "arrow.clockwise")
            }
            .keyboardShortcut("r", modifiers: [.command, .shift])
        }
    }

    // MARK: - Now Overlay

    /// A translucent overlay shown during active recording / transcription,
    /// giving real-time feedback without leaving the history window.
    private var nowOverlay: some View {
        VStack(spacing: 16) {
            Spacer()

            if appState.isRecording {
                recordingOverlayContent
            } else if appState.isTranscribing {
                transcribingOverlayContent
            }

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.ultraThinMaterial)
        .onTapGesture {
            // Dismiss only if not active.
            if !appState.isRecording && !appState.isTranscribing {
                showNowOverlay = false
            }
        }
    }

    private var recordingOverlayContent: some View {
        VStack(spacing: 16) {
            Circle()
                .fill(.red)
                .frame(width: 12, height: 12)
                .modifier(OverlayPulse())

            WaveformView.expanded(samples: appState.meteringSamples, color: .green)
                .frame(width: 300, height: 80)

            Text(formattedElapsed)
                .font(.system(size: 28, weight: .light, design: .monospaced))
                .monospacedDigit()

            Button {
                appState.stopRecording()
            } label: {
                Label("Stop Recording", systemImage: "stop.fill")
                    .font(.headline)
            }
            .buttonStyle(.borderedProminent)
            .tint(.red)
            .controlSize(.large)
        }
    }

    private var transcribingOverlayContent: some View {
        VStack(spacing: 16) {
            Text("Transcribing...")
                .font(.headline)
                .foregroundStyle(.orange)

            ProgressView(value: Double(appState.transcriptionProgress))
                .progressViewStyle(.linear)
                .frame(width: 240)
                .tint(.orange)

            Text("\(Int(appState.transcriptionProgress * 100))%")
                .font(.system(size: 18, weight: .medium, design: .monospaced))
                .foregroundStyle(.secondary)
                .monospacedDigit()
        }
    }

    private var formattedElapsed: String {
        let mins = appState.recordingElapsedSeconds / 60
        let secs = appState.recordingElapsedSeconds % 60
        return String(format: "%d:%02d", mins, secs)
    }
}

// MARK: - SessionDetailView

/// Full detail view for a single session, shown in the detail column of
/// the NavigationSplitView.
private struct SessionDetailView: View {
    let session: VRSession

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                // Header.
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(formattedDate)
                            .font(.title2)
                            .fontWeight(.semibold)
                        Text("Duration: \(formattedDuration)  |  Status: \(session.status ?? "unknown")")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                }

                Divider()

                // Transcript.
                if let transcript = session.transcript, !transcript.isEmpty {
                    Text(transcript)
                        .font(.body)
                        .textSelection(.enabled)
                } else {
                    Text("No transcript available.")
                        .foregroundStyle(.tertiary)
                        .italic()
                }
            }
            .padding(20)
        }
    }

    private var formattedDate: String {
        let date = Date(timeIntervalSince1970: TimeInterval(session.createdAt))
        let formatter = DateFormatter()
        formatter.dateStyle = .long
        formatter.timeStyle = .medium
        return formatter.string(from: date)
    }

    private var formattedDuration: String {
        let totalSeconds = session.durationMs / 1000
        let minutes = totalSeconds / 60
        let seconds = totalSeconds % 60
        return String(format: "%d:%02d", minutes, seconds)
    }
}

// MARK: - OverlayPulse

private struct OverlayPulse: ViewModifier {
    @State private var isPulsing = false

    func body(content: Content) -> some View {
        content
            .scaleEffect(isPulsing ? 1.3 : 1.0)
            .opacity(isPulsing ? 0.5 : 1.0)
            .onAppear {
                withAnimation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true)) {
                    isPulsing = true
                }
            }
    }
}
