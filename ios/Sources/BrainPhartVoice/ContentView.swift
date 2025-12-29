import SwiftUI
#if os(macOS)
import AppKit
#endif

// MARK: - Main Content View

struct ContentView: View {
    @EnvironmentObject var appState: AppState
    @StateObject private var audioRecorder = AudioRecorder()
    @State private var recordings: [RecordingItem] = []
    @State private var selectedRecording: RecordingItem?
    @State private var editedTranscript: String = ""

    // Notification publishers
    let toggleRecordingPublisher = NotificationCenter.default.publisher(for: .toggleRecording)
    let cancelRecordingPublisher = NotificationCenter.default.publisher(for: .cancelRecording)
    let transcriptionCompletePublisher = NotificationCenter.default.publisher(for: .transcriptionComplete)

    var body: some View {
        Group {
            switch appState.windowMode {
            case .micro:
                MicroModeView(
                    audioRecorder: audioRecorder,
                    onStartStop: handleStartStop,
                    onCancel: handleCancel
                )

            case .medium:
                MediumModeView(
                    audioRecorder: audioRecorder,
                    onStartStop: handleStartStop,
                    onCancel: handleCancel
                )

            case .full:
                FullModeView(
                    audioRecorder: audioRecorder,
                    recordings: $recordings,
                    selectedRecording: $selectedRecording,
                    editedTranscript: $editedTranscript,
                    onStartStop: handleStartStop,
                    onCancel: handleCancel,
                    onSelect: selectRecording,
                    onSave: saveTranscript,
                    onDelete: deleteRecording,
                    onRefresh: loadRecordings
                )
            }
        }
        .onAppear {
            loadRecordings()
        }
        .onReceive(toggleRecordingPublisher) { _ in
            handleStartStop()
        }
        .onReceive(cancelRecordingPublisher) { _ in
            if audioRecorder.isRecording {
                handleCancel()
            }
        }
        .onReceive(transcriptionCompletePublisher) { notification in
            if let sessionId = notification.object as? String {
                loadRecordings()
                if selectedRecording?.id == sessionId {
                    let transcript = DatabaseManager.shared.getTranscript(sessionId: sessionId)
                    editedTranscript = transcript
                    handleTranscriptionComplete(transcript)
                }
            }
        }
    }

    // MARK: - Actions

    private func handleStartStop() {
        if audioRecorder.isRecording {
            // Stop recording
            audioRecorder.stopRecording()
            loadRecordings()

            // Select newest recording
            if let newest = recordings.first {
                selectRecording(newest)
            }
        } else {
            // Start recording
            let sessionId = UUID().uuidString
            DatabaseManager.shared.createSession(id: sessionId)

            Task {
                await audioRecorder.startRecording(sessionId: sessionId)
            }
        }
    }

    private func handleCancel() {
        audioRecorder.cancelRecording()
        loadRecordings()
    }

    private func loadRecordings() {
        let sessions = DatabaseManager.shared.getAllSessions()
        recordings = sessions.map { session in
            let transcript = DatabaseManager.shared.getTranscript(sessionId: session.id)
            let durationMs = DatabaseManager.shared.getSessionDuration(sessionId: session.id)
            return RecordingItem(
                id: session.id,
                createdAt: session.createdAt,
                transcript: transcript,
                status: session.status,
                durationMs: durationMs
            )
        }

        // Auto-select first if none selected
        if selectedRecording == nil, let first = recordings.first {
            selectRecording(first)
        }
    }

    private func selectRecording(_ recording: RecordingItem) {
        selectedRecording = recording
        editedTranscript = recording.transcript
    }

    private func saveTranscript() {
        guard let selected = selectedRecording else { return }
        DatabaseManager.shared.saveTranscriptVersion(
            sessionId: selected.id,
            content: editedTranscript,
            versionType: "user_edit"
        )
        loadRecordings()
    }

    private func deleteRecording(_ recording: RecordingItem) {
        if selectedRecording?.id == recording.id {
            selectedRecording = nil
            editedTranscript = ""
        }
        DatabaseManager.shared.deleteSession(id: recording.id)
        loadRecordings()

        // Select first available
        if selectedRecording == nil, let first = recordings.first {
            selectRecording(first)
        }
    }

    private func handleTranscriptionComplete(_ transcript: String) {
        guard !transcript.isEmpty else { return }

        // Copy to clipboard
        #if os(macOS)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(transcript, forType: .string)
        print("Copied to clipboard: \(transcript.prefix(50))...")

        // Auto-paste if in floating mode
        if appState.windowMode != .full {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                AppState.shared.restoreFocus()
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                    simulatePaste()
                }
            }
        }
        #endif
    }
}

// MARK: - Recording Item Model

struct RecordingItem: Identifiable, Equatable {
    let id: String
    let createdAt: Int
    let transcript: String
    let status: String
    let durationMs: Int

    var dateString: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM dd, HH:mm"
        return formatter.string(from: Date(timeIntervalSince1970: TimeInterval(createdAt)))
    }

    var durationString: String {
        let seconds = durationMs / 1000
        let mins = seconds / 60
        let secs = seconds % 60
        return String(format: "%d:%02d", mins, secs)
    }

    var title: String {
        if transcript.isEmpty {
            return "Recording \(dateString)"
        }
        let preview = transcript.prefix(40).replacingOccurrences(of: "\n", with: " ")
        return String(preview) + (transcript.count > 40 ? "..." : "")
    }

    var hasTranscript: Bool { !transcript.isEmpty }
    var isProcessing: Bool { status == "complete" && !hasTranscript }
}

// MARK: - Session Model

struct Session {
    let id: String
    let createdAt: Int
    let status: String
}

// MARK: - Simulate Paste (macOS)

#if os(macOS)
func simulatePaste() {
    let source = CGEventSource(stateID: .hidSystemState)

    // Key down: Cmd+V
    let keyDown = CGEvent(keyboardEventSource: source, virtualKey: 0x09, keyDown: true)
    keyDown?.flags = .maskCommand
    keyDown?.post(tap: .cghidEventTap)

    // Key up: Cmd+V
    let keyUp = CGEvent(keyboardEventSource: source, virtualKey: 0x09, keyDown: false)
    keyUp?.flags = .maskCommand
    keyUp?.post(tap: .cghidEventTap)
}
#endif
