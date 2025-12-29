import SwiftUI
import UserNotifications

// MARK: - Main Content View Wrapper (Coordinates with floating pill)

struct MainContentView: View {
    @EnvironmentObject var appState: AppState
    @StateObject private var recorder = AudioRecorder()
    @State private var sessionId = UUID().uuidString
    @State private var selectedTab = 0

    var body: some View {
        ZStack {
            TabView(selection: $selectedTab) {
            // MARK: - Record Tab
            RecordingView(recorder: recorder, sessionId: $sessionId, appState: appState)
                .tabItem {
                    Image(systemName: "mic.fill")
                    Text("Record")
                }
                .tag(0)

            // MARK: - History Tab
            HistoryView()
                .tabItem {
                    Image(systemName: "clock.arrow.circlepath")
                    Text("History")
                }
                .tag(1)

            // MARK: - Keyboard Setup Tab
            KeyboardSetupView()
                .tabItem {
                    Image(systemName: "keyboard")
                    Text("Keyboard")
                }
                .tag(2)
        }
        .onReceive(NotificationCenter.default.publisher(for: .toggleRecording)) { _ in
            if recorder.isRecording {
                stopAndTranscribe()
            } else {
                startRecording()
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .startRecordingFromShortcut)) { _ in
            if !recorder.isRecording {
                selectedTab = 0
                startRecording()
            }
        }
        .onAppear {
            requestNotificationPermission()
            checkForPendingKeyboardAudio()
        }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.willEnterForegroundNotification)) { _ in
            checkForPendingKeyboardAudio()
        }
        .onReceive(NotificationCenter.default.publisher(for: .transcribePendingAudio)) { _ in
            checkForPendingKeyboardAudio()
        }
        }  // End ZStack
        .fullScreenCover(isPresented: $appState.showEditView) {
            EditTranscriptView()
                .environmentObject(appState)
        }
    }

    private func requestNotificationPermission() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { granted, _ in
            print("Notification permission: \(granted)")
        }
    }

    private func startRecording() {
        sessionId = UUID().uuidString
        appState.latestTranscript = ""
        LiveActivityManager.shared.startActivity(sessionId: sessionId)
        Task {
            await recorder.startRecording(sessionId: sessionId)
        }
    }

    private func stopAndTranscribe() {
        LiveActivityManager.shared.endActivity(finalDuration: recorder.recordingDuration)
        recorder.stopRecording()

        Task {
            appState.isTranscribing = true

            do {
                guard let audioData = recorder.getLastRecordingData() else {
                    throw TranscriptionError.formatError
                }

                let result = try await TranscriptionManager.shared.transcribe(audioData: audioData)
                DatabaseManager.shared.saveTranscript(sessionId: sessionId, transcript: result)

                await MainActor.run {
                    appState.latestTranscript = result
                    UIPasteboard.general.string = result
                    SharedStorage.shared.saveTranscript(result)
                }

                sendTranscriptNotification(preview: String(result.prefix(100)))
            } catch {
                print("Transcription error: \(error)")
            }

            await MainActor.run {
                appState.isTranscribing = false
            }
        }
    }

    // Check for audio recorded from keyboard extension and transcribe it
    private func checkForPendingKeyboardAudio() {
        let appGroupID = "group.com.brainphart.voicerecorder"
        guard let defaults = UserDefaults(suiteName: appGroupID),
              let audioData = defaults.data(forKey: "pendingAudioData"),
              let timestamp = defaults.double(forKey: "pendingAudioTimestamp") as Double?,
              timestamp > 0 else { return }

        // Only process if audio is recent (within last 5 minutes)
        let age = Date().timeIntervalSince1970 - timestamp
        guard age < 300 else {
            defaults.removeObject(forKey: "pendingAudioData")
            defaults.removeObject(forKey: "pendingAudioTimestamp")
            return
        }

        print("Found pending keyboard audio: \(audioData.count) bytes")

        // Clear the pending audio immediately to prevent reprocessing
        defaults.removeObject(forKey: "pendingAudioData")
        defaults.removeObject(forKey: "pendingAudioTimestamp")
        defaults.synchronize()

        // Transcribe the audio
        Task {
            await MainActor.run {
                appState.isTranscribing = true
            }

            do {
                let result = try await TranscriptionManager.shared.transcribe(audioData: audioData)

                await MainActor.run {
                    appState.latestTranscript = result
                    appState.isTranscribing = false

                    // Save to shared storage for keyboard to pick up
                    SharedStorage.shared.saveTranscript(result)

                    // Also copy to clipboard
                    UIPasteboard.general.string = result

                    print("Keyboard audio transcribed: \(result.prefix(50))...")
                }
            } catch {
                print("Keyboard audio transcription error: \(error)")
                await MainActor.run {
                    appState.isTranscribing = false
                }
            }
        }
    }

    private func sendTranscriptNotification(preview: String) {
        let content = UNMutableNotificationContent()
        content.title = "Transcript Ready"
        content.body = "\(preview)..."
        content.sound = .default

        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request)
    }
}

// MARK: - Recording View (Main recording interface)

struct RecordingView: View {
    @ObservedObject var recorder: AudioRecorder
    @Binding var sessionId: String
    @ObservedObject var appState: AppState
    @State private var showFullTranscript = false

    var body: some View {
        NavigationStack {
            ZStack {
                Color.black.ignoresSafeArea()

                VStack(spacing: 24) {
                    Spacer()

                    // Timer or idle state
                    if recorder.isRecording {
                        Text(formatTime(recorder.recordingDuration))
                            .font(.system(size: 64, weight: .thin, design: .monospaced))
                            .foregroundColor(.white)

                        MiniWaveform(level: recorder.audioLevel, isRecording: true)
                            .frame(width: 200, height: 60)
                    } else if appState.isTranscribing {
                        // Transcribing state - show progress
                        VStack(spacing: 20) {
                            ProgressView()
                                .scaleEffect(2)
                                .tint(.white)

                            Text("Transcribing...")
                                .font(.title2)
                                .foregroundColor(.white)

                            Text("Processing your recording")
                                .font(.caption)
                                .foregroundColor(.gray)
                        }
                    } else if !appState.latestTranscript.isEmpty {
                        // Show transcript result
                        VStack(spacing: 16) {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.system(size: 50))
                                .foregroundColor(.green)

                            Text("Transcription Complete")
                                .font(.headline)
                                .foregroundColor(.white)

                            // Transcript preview
                            Text(appState.latestTranscript)
                                .font(.body)
                                .foregroundColor(.white.opacity(0.9))
                                .multilineTextAlignment(.center)
                                .lineLimit(4)
                                .padding(.horizontal, 20)

                            // Action buttons
                            HStack(spacing: 16) {
                                Button(action: {
                                    UIPasteboard.general.string = appState.latestTranscript
                                }) {
                                    Label("Copy", systemImage: "doc.on.clipboard")
                                        .font(.subheadline.bold())
                                        .foregroundColor(.white)
                                        .padding(.horizontal, 20)
                                        .padding(.vertical, 12)
                                        .background(Capsule().fill(Color.blue))
                                }

                                Button(action: {
                                    showFullTranscript = true
                                }) {
                                    Label("View", systemImage: "arrow.up.right")
                                        .font(.subheadline.bold())
                                        .foregroundColor(.white)
                                        .padding(.horizontal, 20)
                                        .padding(.vertical, 12)
                                        .background(Capsule().fill(Color.white.opacity(0.2)))
                                }
                            }
                            .padding(.top, 8)
                        }
                    } else {
                        // Idle state
                        VStack(spacing: 16) {
                            Image(systemName: "mic.fill")
                                .font(.system(size: 80))
                                .foregroundColor(.red.opacity(0.8))

                            Text("Tap to Record")
                                .font(.title2)
                                .foregroundColor(.gray)

                            Text("Or use the Keyboard Extension in any app")
                                .font(.caption)
                                .foregroundColor(.gray.opacity(0.6))
                                .multilineTextAlignment(.center)
                        }
                    }

                    Spacer()

                    // Big record button
                    Button(action: {
                        NotificationCenter.default.post(name: .toggleRecording, object: nil)
                    }) {
                        ZStack {
                            Circle()
                                .stroke(Color.white, lineWidth: 5)
                                .frame(width: 100, height: 100)

                            if recorder.isRecording {
                                RoundedRectangle(cornerRadius: 8)
                                    .fill(Color.white)
                                    .frame(width: 36, height: 36)
                            } else {
                                Circle()
                                    .fill(Color.red)
                                    .frame(width: 76, height: 76)
                            }
                        }
                    }
                    .disabled(appState.isTranscribing)
                    .opacity(appState.isTranscribing ? 0.5 : 1)

                    Spacer()
                        .frame(height: 60)
                }
            }
            .navigationTitle("Voice Recorder")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbarBackground(Color.black, for: .navigationBar)
            .fullScreenCover(isPresented: $showFullTranscript) {
                FullTranscriptView(
                    transcript: appState.latestTranscript,
                    audioData: recorder.getLastRecordingData()
                )
            }
        }
    }

    private func formatTime(_ duration: TimeInterval) -> String {
        let mins = Int(duration) / 60
        let secs = Int(duration) % 60
        return String(format: "%02d:%02d", mins, secs)
    }
}

// MARK: - Keyboard Setup View

struct KeyboardSetupView: View {
    var body: some View {
        NavigationStack {
            List {
                Section {
                    VStack(alignment: .leading, spacing: 16) {
                        HStack {
                            Image(systemName: "keyboard.badge.ellipsis")
                                .font(.system(size: 40))
                                .foregroundColor(.blue)
                            Spacer()
                        }

                        Text("Use Voice Recorder in ANY App")
                            .font(.headline)

                        Text("The keyboard extension lets you record and transcribe directly into any text field - Messages, Notes, Email, anywhere!")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                    .padding(.vertical, 8)
                }

                Section("Setup Steps") {
                    SetupStepRow(number: 1, title: "Open Settings", detail: "Go to Settings app")
                    SetupStepRow(number: 2, title: "General -> Keyboard", detail: "Tap General, then Keyboard")
                    SetupStepRow(number: 3, title: "Keyboards -> Add", detail: "Tap Keyboards, then Add New Keyboard")
                    SetupStepRow(number: 4, title: "Select Transcript", detail: "Find and tap 'Transcript' keyboard")
                    SetupStepRow(number: 5, title: "Allow Full Access", detail: "Enable Full Access for transcripts")
                }

                Section("How to Use") {
                    Label("Open any app with a text field", systemImage: "1.circle.fill")
                    Label("Tap the text field to show keyboard", systemImage: "2.circle.fill")
                    Label("Long-press globe, select Transcript", systemImage: "3.circle.fill")
                    Label("Tap 'Paste Transcript' to insert text", systemImage: "4.circle.fill")
                }

                Section {
                    Button(action: openSettings) {
                        HStack {
                            Text("Open Settings")
                            Spacer()
                            Image(systemName: "arrow.up.forward.app")
                        }
                    }
                }
            }
            .navigationTitle("Keyboard Setup")
        }
    }

    private func openSettings() {
        if let url = URL(string: UIApplication.openSettingsURLString) {
            UIApplication.shared.open(url)
        }
    }
}

// MARK: - Setup Step Row

struct SetupStepRow: View {
    let number: Int
    let title: String
    let detail: String

    var body: some View {
        HStack(spacing: 16) {
            ZStack {
                Circle()
                    .fill(Color.blue)
                    .frame(width: 32, height: 32)
                Text("\(number)")
                    .font(.headline)
                    .foregroundColor(.white)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline)
                    .fontWeight(.medium)
                Text(detail)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Mini Waveform

struct MiniWaveform: View {
    let level: Float
    let isRecording: Bool
    private let barCount = 8

    var body: some View {
        HStack(spacing: 2) {
            ForEach(0..<barCount, id: \.self) { index in
                RoundedRectangle(cornerRadius: 1)
                    .fill(Color.white)
                    .frame(width: 4, height: barHeight(for: index))
                    .animation(.easeOut(duration: 0.1), value: level)
            }
        }
    }

    private func barHeight(for index: Int) -> CGFloat {
        guard isRecording else { return 4 }
        let base = CGFloat(level) * 24
        let variation = sin(Double(index) * 0.8 + Double(level) * 8) * 0.4 + 0.6
        return max(4, base * CGFloat(variation))
    }
}

// MARK: - Full Transcript View (Full Screen)

struct FullTranscriptView: View {
    @Environment(\.dismiss) private var dismiss
    let transcript: String
    let audioData: Data?

    @State private var editedTranscript: String = ""
    @StateObject private var audioPlayer = AudioPlayer()
    @FocusState private var isEditing: Bool

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Audio playback controls
                if audioData != nil {
                    AudioPlaybackBar(audioPlayer: audioPlayer, audioData: audioData)
                }

                // Editable transcript with spell check
                ScrollView {
                    TextEditor(text: $editedTranscript)
                        .font(.body)
                        .foregroundColor(.primary)
                        .scrollContentBackground(.hidden)
                        .background(Color.clear)
                        .frame(minHeight: 300)
                        .focused($isEditing)
                        .autocorrectionDisabled(false)  // Enable spell check
                        .textContentType(.none)
                }
                .padding()

                // Copy button at bottom
                Button(action: {
                    UIPasteboard.general.string = editedTranscript
                }) {
                    HStack {
                        Image(systemName: "doc.on.clipboard")
                        Text("Copy to Clipboard")
                    }
                    .font(.headline)
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.blue)
                    .cornerRadius(12)
                }
                .padding()
            }
            .navigationTitle("Transcript")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Done") {
                        audioPlayer.stop()
                        dismiss()
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button(isEditing ? "Done Editing" : "Edit") {
                        isEditing.toggle()
                    }
                }
            }
            .onAppear {
                editedTranscript = transcript
            }
            .onDisappear {
                audioPlayer.stop()
            }
        }
    }
}

// MARK: - Audio Playback Bar

struct AudioPlaybackBar: View {
    @ObservedObject var audioPlayer: AudioPlayer
    let audioData: Data?

    var body: some View {
        HStack(spacing: 16) {
            // Play/Pause button
            Button(action: {
                if audioPlayer.isPlaying {
                    audioPlayer.pause()
                } else if let data = audioData {
                    audioPlayer.play(data: data)
                }
            }) {
                Image(systemName: audioPlayer.isPlaying ? "pause.circle.fill" : "play.circle.fill")
                    .font(.system(size: 44))
                    .foregroundColor(.blue)
            }

            // Progress
            VStack(alignment: .leading, spacing: 4) {
                // Progress bar
                GeometryReader { geometry in
                    ZStack(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 2)
                            .fill(Color.secondary.opacity(0.3))
                            .frame(height: 4)

                        RoundedRectangle(cornerRadius: 2)
                            .fill(Color.blue)
                            .frame(width: geometry.size.width * progress, height: 4)
                    }
                }
                .frame(height: 4)

                // Time
                HStack {
                    Text(formatTime(audioPlayer.currentTime))
                        .font(.caption2)
                        .foregroundColor(.secondary)
                        .monospacedDigit()
                    Spacer()
                    Text(formatTime(audioPlayer.duration))
                        .font(.caption2)
                        .foregroundColor(.secondary)
                        .monospacedDigit()
                }
            }
        }
        .padding()
        .background(Color(.systemGray6))
    }

    private var progress: Double {
        guard audioPlayer.duration > 0 else { return 0 }
        return audioPlayer.currentTime / audioPlayer.duration
    }

    private func formatTime(_ seconds: TimeInterval) -> String {
        let mins = Int(seconds) / 60
        let secs = Int(seconds) % 60
        return String(format: "%d:%02d", mins, secs)
    }
}

// MARK: - History View

struct HistoryView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var audioPlayer = AudioPlayer()
    @State private var sessions: [DatabaseManager.SessionInfo] = []
    @State private var expandedSessionId: String? = nil
    @State private var sessionToDelete: DatabaseManager.SessionInfo? = nil
    @State private var showDeleteConfirmation = false
    @State private var playingSessionId: String? = nil

    var body: some View {
        NavigationStack {
            Group {
                if sessions.isEmpty {
                    VStack(spacing: 16) {
                        Image(systemName: "waveform")
                            .font(.system(size: 48))
                            .foregroundColor(.secondary)
                        Text("No recordings yet")
                            .font(.headline)
                            .foregroundColor(.secondary)
                        Text("Tap the mic to start recording")
                            .font(.subheadline)
                            .foregroundColor(.secondary.opacity(0.7))
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    List {
                        ForEach(sessions, id: \.id) { session in
                            SessionRowView(
                                session: session,
                                isExpanded: expandedSessionId == session.id,
                                isPlaying: playingSessionId == session.id && audioPlayer.isPlaying,
                                audioPlayer: audioPlayer,
                                onTap: {
                                    withAnimation(.easeInOut(duration: 0.2)) {
                                        if expandedSessionId == session.id {
                                            expandedSessionId = nil
                                        } else {
                                            expandedSessionId = session.id
                                        }
                                    }
                                },
                                onPlay: {
                                    playSession(session)
                                },
                                onDelete: {
                                    sessionToDelete = session
                                    showDeleteConfirmation = true
                                },
                                onTranscriptionComplete: { _ in
                                    // Refresh list when transcription completes
                                    loadSessions()
                                }
                            )
                            .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
                            .listRowSeparator(.hidden)
                        }
                    }
                    .listStyle(.plain)
                    .refreshable {
                        loadSessions()
                    }
                }
            }
            .navigationTitle("Recordings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") {
                        audioPlayer.stop()
                        dismiss()
                    }
                }
            }
            .onAppear {
                loadSessions()
            }
            .onDisappear {
                audioPlayer.stop()
            }
            .onReceive(NotificationCenter.default.publisher(for: UIApplication.willEnterForegroundNotification)) { _ in
                // Auto-refresh when app comes to foreground (picks up keyboard transcriptions)
                loadSessions()
            }
            .alert("Delete Recording?", isPresented: $showDeleteConfirmation) {
                Button("Cancel", role: .cancel) {
                    sessionToDelete = nil
                }
                Button("Delete", role: .destructive) {
                    if let session = sessionToDelete {
                        deleteSession(session)
                    }
                    sessionToDelete = nil
                }
            } message: {
                if let session = sessionToDelete {
                    Text("This will permanently delete the recording from \(formatDate(session.createdAt)).")
                }
            }
        }
    }

    private func loadSessions() {
        sessions = DatabaseManager.shared.getAllSessions()
    }

    private func playSession(_ session: DatabaseManager.SessionInfo) {
        if playingSessionId == session.id && audioPlayer.isPlaying {
            audioPlayer.pause()
        } else if playingSessionId == session.id {
            audioPlayer.resume()
        } else {
            // Load and play new session
            if let audioData = DatabaseManager.shared.getSessionAudio(sessionId: session.id) {
                playingSessionId = session.id
                audioPlayer.play(data: audioData)
            }
        }
    }

    private func deleteSession(_ session: DatabaseManager.SessionInfo) {
        if playingSessionId == session.id {
            audioPlayer.stop()
            playingSessionId = nil
        }
        DatabaseManager.shared.deleteSession(sessionId: session.id)
        loadSessions()
    }

    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
}

// MARK: - Session Row View

struct SessionRowView: View {
    let session: DatabaseManager.SessionInfo
    let isExpanded: Bool
    let isPlaying: Bool
    @ObservedObject var audioPlayer: AudioPlayer
    let onTap: () -> Void
    let onPlay: () -> Void
    let onDelete: () -> Void
    var onTranscriptionComplete: ((String) -> Void)? = nil

    @State private var showTranscriptEditor = false
    @State private var isRetryingTranscription = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Main row content
            HStack(spacing: 12) {
                // Play button
                Button(action: onPlay) {
                    ZStack {
                        Circle()
                            .fill(Color.blue.opacity(0.15))
                            .frame(width: 44, height: 44)

                        Image(systemName: isPlaying ? "pause.fill" : "play.fill")
                            .font(.system(size: 18))
                            .foregroundColor(.blue)
                    }
                }
                .buttonStyle(.plain)

                // Session info
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        Text(formatDate(session.createdAt))
                            .font(.subheadline)
                            .fontWeight(.medium)

                        // Keyboard indicator
                        if session.source == "keyboard" {
                            Image(systemName: "keyboard")
                                .font(.caption)
                                .foregroundColor(.blue)
                        }
                    }

                    HStack(spacing: 8) {
                        Label(formatDuration(session.totalDurationMs), systemImage: "clock")
                            .font(.caption)
                            .foregroundColor(.secondary)

                        if session.status == "recording" {
                            Label("Recording", systemImage: "record.circle")
                                .font(.caption)
                                .foregroundColor(.red)
                        }

                        // Show green checkmark if has transcript
                        if session.transcript != nil && !session.transcript!.isEmpty {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.caption)
                                .foregroundColor(.green)
                        }
                    }
                }

                Spacer()

                // Expand indicator
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.secondary)
                    .rotationEffect(.degrees(isExpanded ? 90 : 0))
            }
            .contentShape(Rectangle())
            .onTapGesture {
                onTap()
            }

            // Expanded content
            if isExpanded {
                VStack(alignment: .leading, spacing: 12) {
                    // Progress bar (when playing this session)
                    if isPlaying || (audioPlayer.duration > 0 && audioPlayer.currentTime > 0) {
                        PlaybackProgressView(
                            currentTime: audioPlayer.currentTime,
                            duration: audioPlayer.duration,
                            onSeek: { time in
                                audioPlayer.seek(to: time)
                            }
                        )
                    }

                    // Transcript section
                    if let transcript = session.transcript, !transcript.isEmpty {
                        // Has transcript - show green tick, tap to open editor
                        Button(action: { showTranscriptEditor = true }) {
                            HStack(spacing: 8) {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundColor(.green)
                                    .font(.system(size: 16))

                                Text("Transcription")
                                    .font(.subheadline)
                                    .foregroundColor(.primary)

                                Spacer()

                                Image(systemName: "chevron.right")
                                    .font(.system(size: 12))
                                    .foregroundColor(.secondary)
                            }
                            .padding(.vertical, 8)
                            .padding(.horizontal, 12)
                            .background(
                                RoundedRectangle(cornerRadius: 8)
                                    .fill(Color.green.opacity(0.1))
                            )
                        }
                        .buttonStyle(.plain)
                    } else {
                        // No transcript available - show retry button
                        HStack(spacing: 12) {
                            if isRetryingTranscription {
                                ProgressView()
                                    .scaleEffect(0.8)
                                Text("Transcribing...")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            } else {
                                Button(action: retryTranscription) {
                                    HStack(spacing: 8) {
                                        Image(systemName: "arrow.clockwise")
                                            .font(.system(size: 14))
                                        Text("Retry Transcription")
                                            .font(.caption)
                                    }
                                    .foregroundColor(.blue)
                                    .padding(.vertical, 8)
                                    .padding(.horizontal, 12)
                                    .background(
                                        RoundedRectangle(cornerRadius: 8)
                                            .fill(Color.blue.opacity(0.1))
                                    )
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(.vertical, 4)
                    }

                    // Delete button
                    Button(action: onDelete) {
                        Label("Delete Recording", systemImage: "trash")
                            .font(.subheadline)
                            .foregroundColor(.red)
                    }
                    .buttonStyle(.plain)
                }
                .padding(.leading, 56) // Align with text, not play button
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 12)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(.systemGray6))
        )
        .fullScreenCover(isPresented: $showTranscriptEditor) {
            SessionTranscriptEditor(
                session: session,
                audioData: DatabaseManager.shared.getSessionAudio(sessionId: session.id)
            )
        }
    }

    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        if Calendar.current.isDateInToday(date) {
            formatter.dateFormat = "'Today at' h:mm a"
        } else if Calendar.current.isDateInYesterday(date) {
            formatter.dateFormat = "'Yesterday at' h:mm a"
        } else {
            formatter.dateStyle = .medium
            formatter.timeStyle = .short
        }
        return formatter.string(from: date)
    }

    private func formatDuration(_ ms: Int) -> String {
        let totalSeconds = ms / 1000
        let minutes = totalSeconds / 60
        let seconds = totalSeconds % 60
        if minutes > 0 {
            return "\(minutes)m \(seconds)s"
        } else {
            return "\(seconds)s"
        }
    }

    private func retryTranscription() {
        isRetryingTranscription = true

        Task {
            do {
                guard let audioData = DatabaseManager.shared.getSessionAudio(sessionId: session.id) else {
                    print("No audio data for session: \(session.id)")
                    await MainActor.run { isRetryingTranscription = false }
                    return
                }

                let result = try await TranscriptionManager.shared.transcribe(audioData: audioData)

                // Save to database
                DatabaseManager.shared.saveTranscript(sessionId: session.id, transcript: result)

                // Copy to clipboard
                await MainActor.run {
                    UIPasteboard.general.string = result
                    isRetryingTranscription = false
                    onTranscriptionComplete?(result)
                }

                print("Retry transcription complete: \(result.prefix(50))...")
            } catch {
                print("Retry transcription failed: \(error)")
                await MainActor.run {
                    isRetryingTranscription = false
                }
            }
        }
    }
}

// MARK: - Session Transcript Editor

struct SessionTranscriptEditor: View {
    @Environment(\.dismiss) private var dismiss
    let session: DatabaseManager.SessionInfo
    let audioData: Data?

    @State private var editedTranscript: String = ""
    @StateObject private var audioPlayer = AudioPlayer()
    @FocusState private var isEditing: Bool

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Audio playback controls
                if audioData != nil {
                    AudioPlaybackBar(audioPlayer: audioPlayer, audioData: audioData)
                }

                // Editable transcript with spell check
                ScrollView {
                    TextEditor(text: $editedTranscript)
                        .font(.body)
                        .foregroundColor(.primary)
                        .scrollContentBackground(.hidden)
                        .background(Color.clear)
                        .frame(minHeight: 300)
                        .focused($isEditing)
                        .autocorrectionDisabled(false)
                        .textContentType(.none)
                }
                .padding()

                // Copy button at bottom
                Button(action: {
                    UIPasteboard.general.string = editedTranscript
                    // Also save back to database if edited
                    if editedTranscript != session.transcript {
                        DatabaseManager.shared.saveTranscript(sessionId: session.id, transcript: editedTranscript)
                    }
                }) {
                    HStack {
                        Image(systemName: "doc.on.clipboard")
                        Text("Copy to Clipboard")
                    }
                    .font(.headline)
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.blue)
                    .cornerRadius(12)
                }
                .padding()
            }
            .navigationTitle("Transcript")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Done") {
                        audioPlayer.stop()
                        dismiss()
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button(isEditing ? "Done Editing" : "Edit") {
                        isEditing.toggle()
                    }
                }
            }
            .onAppear {
                editedTranscript = session.transcript ?? ""
            }
            .onDisappear {
                audioPlayer.stop()
            }
        }
    }
}

// MARK: - Playback Progress View

struct PlaybackProgressView: View {
    let currentTime: TimeInterval
    let duration: TimeInterval
    let onSeek: (TimeInterval) -> Void

    @State private var isDragging = false
    @State private var dragValue: Double = 0

    var progress: Double {
        guard duration > 0 else { return 0 }
        return isDragging ? dragValue : currentTime / duration
    }

    var body: some View {
        VStack(spacing: 4) {
            // Progress slider
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    // Background track
                    RoundedRectangle(cornerRadius: 2)
                        .fill(Color.secondary.opacity(0.3))
                        .frame(height: 4)

                    // Progress track
                    RoundedRectangle(cornerRadius: 2)
                        .fill(Color.blue)
                        .frame(width: geometry.size.width * progress, height: 4)

                    // Thumb
                    Circle()
                        .fill(Color.blue)
                        .frame(width: 12, height: 12)
                        .offset(x: geometry.size.width * progress - 6)
                }
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { value in
                            isDragging = true
                            let newProgress = max(0, min(1, value.location.x / geometry.size.width))
                            dragValue = newProgress
                        }
                        .onEnded { value in
                            let newProgress = max(0, min(1, value.location.x / geometry.size.width))
                            onSeek(newProgress * duration)
                            isDragging = false
                        }
                )
            }
            .frame(height: 12)

            // Time labels
            HStack {
                Text(formatTime(isDragging ? dragValue * duration : currentTime))
                    .font(.caption2)
                    .foregroundColor(.secondary)
                    .monospacedDigit()

                Spacer()

                Text(formatTime(duration))
                    .font(.caption2)
                    .foregroundColor(.secondary)
                    .monospacedDigit()
            }
        }
    }

    private func formatTime(_ seconds: TimeInterval) -> String {
        let mins = Int(seconds) / 60
        let secs = Int(seconds) % 60
        return String(format: "%d:%02d", mins, secs)
    }
}

// MARK: - Edit Transcript View (opened from keyboard)

struct EditTranscriptView: View {
    @EnvironmentObject var appState: AppState
    @State private var editedText: String = ""
    @FocusState private var isFocused: Bool

    private let appGroupID = "group.com.brainphart.voicerecorder"

    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                // Header - bigger and bolder
                Text("Edit Transcript")
                    .font(.system(size: 28, weight: .bold))
                    .padding(.top, 20)
                    .padding(.bottom, 12)

                // Text editor with LARGE font for easy editing
                TextEditor(text: $editedText)
                    .font(.system(size: 24, weight: .medium))
                    .padding()
                    .background(Color(.secondarySystemBackground))
                    .cornerRadius(16)
                    .padding(.horizontal)
                    .focused($isFocused)
                    .autocorrectionDisabled(false)

                // Word count
                Text("\(editedText.split(separator: " ").count) words")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .padding(.top, 12)

                Spacer()

                // Instructions
                Text("Edit your transcript, then tap 'Copy & Close' to paste the corrected version")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)

                // Action buttons - bigger
                HStack(spacing: 16) {
                    // Cancel button
                    Button(action: cancel) {
                        Text("Cancel")
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundColor(.red)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 16)
                            .background(Color(.tertiarySystemBackground))
                            .cornerRadius(14)
                    }

                    // Update button - prominent green
                    Button(action: updateAndReturn) {
                        Text("Copy & Close")
                            .font(.system(size: 18, weight: .bold))
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 16)
                            .background(Color.green)
                            .cornerRadius(14)
                    }
                }
                .padding()
                .padding(.bottom, 8)
            }
            .navigationBarHidden(true)
        }
        .onAppear {
            editedText = appState.editingTranscript
            isFocused = true
        }
    }

    private func cancel() {
        appState.showEditView = false
    }

    private func updateAndReturn() {
        // Save back to database FIRST if we have a session ID
        // This ensures the specific session is updated before any other storage
        if let sessionId = appState.editingSessionId {
            DatabaseManager.shared.saveTranscript(sessionId: sessionId, transcript: editedText)
            print("[App] Updated transcript for session \(sessionId)")
        } else {
            print("[App] WARNING: No session ID - transcript not saved to database")
        }

        // Save to shared storage for keyboard to pick up (legacy support)
        // Only update latestTranscript if we DON'T have a specific session ID
        // This prevents overwriting the "latest" with edits to older sessions
        if let defaults = UserDefaults(suiteName: appGroupID) {
            defaults.set(editedText, forKey: "updatedTranscript")
            // Only update latestTranscript for new recordings, not edits to old ones
            if appState.editingSessionId == nil {
                defaults.set(editedText, forKey: "latestTranscript")
            }
            defaults.synchronize()
        }

        appState.showEditView = false
        appState.editingSessionId = nil

        // Copy to clipboard as backup
        UIPasteboard.general.string = editedText
    }
}

#Preview {
    MainContentView()
        .environmentObject(AppState.shared)
}
