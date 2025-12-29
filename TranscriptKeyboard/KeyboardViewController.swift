import UIKit
import AVFoundation
import SQLite3

#if canImport(WhisperKit)
import WhisperKit
#endif

// MARK: - BrainPhart Keyboard with WhisperKit Transcription

class KeyboardViewController: UIInputViewController {

    private let appGroupID = "group.com.brainphart.voicerecorder"

    // Audio
    private var audioEngine: AVAudioEngine?
    private var audioBuffer: [Float] = []
    private var sampleRate: Double = 48000
    private var isRecording = false
    private var recordingStartTime: Date?
    private var displayLink: CADisplayLink?
    private var currentLevel: Float = 0
    private var lastRecordedWAV: Data?  // Keep for database storage
    private var lastRecordingDurationMs: Int = 0

    // Transcription
    private var isTranscribing = false
    private var lastSessionId: String?  // Track for edit button
    #if canImport(WhisperKit)
    private var whisperKit: WhisperKit?
    private var isModelLoaded = false
    #endif

    // UI
    private var micButton: UIButton!
    private var timerLabel: UILabel!
    private var statusLabel: UILabel!
    private var waveformView: SimpleWaveform!
    private var editButton: UIButton!
    private var progressBar: UIProgressView!
    private var checkmark: UIImageView!

    // MARK: - Lifecycle

    override func viewDidLoad() {
        super.viewDidLoad()
        setupUI()
        requestMicPermission()
        loadWhisperModel()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
    }

    // MARK: - UI Setup

    private func setupUI() {
        let bg = UIView()
        bg.backgroundColor = UIColor(white: 0.97, alpha: 1)
        bg.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(bg)

        NSLayoutConstraint.activate([
            bg.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            bg.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            bg.topAnchor.constraint(equalTo: view.topAnchor),
            bg.heightAnchor.constraint(equalToConstant: 160)
        ])

        // Mic button - subtle gray, compact
        micButton = UIButton(type: .system)
        micButton.backgroundColor = .systemGray5
        micButton.layer.cornerRadius = 24
        micButton.setImage(UIImage(systemName: "mic.fill", withConfiguration: UIImage.SymbolConfiguration(pointSize: 18)), for: .normal)
        micButton.tintColor = .label
        micButton.translatesAutoresizingMaskIntoConstraints = false
        micButton.addTarget(self, action: #selector(micTapped), for: .touchUpInside)
        micButton.accessibilityLabel = "Record voice"
        micButton.accessibilityHint = "Double tap to start or stop recording"
        micButton.isAccessibilityElement = true
        bg.addSubview(micButton)

        // Timer
        timerLabel = UILabel()
        timerLabel.text = "0:00"
        timerLabel.font = .monospacedDigitSystemFont(ofSize: 14, weight: .medium)
        timerLabel.textColor = .label
        timerLabel.translatesAutoresizingMaskIntoConstraints = false
        timerLabel.isHidden = true
        bg.addSubview(timerLabel)

        // Waveform
        waveformView = SimpleWaveform()
        waveformView.translatesAutoresizingMaskIntoConstraints = false
        waveformView.isHidden = true
        bg.addSubview(waveformView)

        // Progress bar for transcription
        progressBar = UIProgressView(progressViewStyle: .default)
        progressBar.progressTintColor = .systemBlue
        progressBar.translatesAutoresizingMaskIntoConstraints = false
        progressBar.isHidden = true
        bg.addSubview(progressBar)

        // Checkmark for success
        checkmark = UIImageView(image: UIImage(systemName: "checkmark.circle.fill"))
        checkmark.tintColor = .systemGreen
        checkmark.translatesAutoresizingMaskIntoConstraints = false
        checkmark.isHidden = true
        bg.addSubview(checkmark)

        // Status
        statusLabel = UILabel()
        statusLabel.text = "Tap to record"
        statusLabel.font = .systemFont(ofSize: 12)
        statusLabel.textColor = .secondaryLabel
        statusLabel.translatesAutoresizingMaskIntoConstraints = false
        bg.addSubview(statusLabel)

        // Edit button
        editButton = UIButton(type: .system)
        editButton.setImage(UIImage(systemName: "pencil.circle.fill", withConfiguration: UIImage.SymbolConfiguration(pointSize: 20)), for: .normal)
        editButton.tintColor = .systemBlue
        editButton.translatesAutoresizingMaskIntoConstraints = false
        editButton.addTarget(self, action: #selector(editTapped), for: .touchUpInside)
        editButton.isHidden = true
        editButton.accessibilityLabel = "Edit transcription"
        editButton.accessibilityHint = "Double tap to open app and edit the transcript"
        editButton.isAccessibilityElement = true
        bg.addSubview(editButton)

        // Globe (keyboard switcher)
        let globe = UIButton(type: .system)
        globe.setImage(UIImage(systemName: "globe"), for: .normal)
        globe.tintColor = .secondaryLabel
        globe.translatesAutoresizingMaskIntoConstraints = false
        globe.addTarget(self, action: #selector(handleInputModeList(from:with:)), for: .allTouchEvents)
        globe.accessibilityLabel = "Switch keyboard"
        globe.accessibilityHint = "Double tap to switch to another keyboard"
        globe.isAccessibilityElement = true
        bg.addSubview(globe)

        // Delete
        let del = UIButton(type: .system)
        del.setImage(UIImage(systemName: "delete.left"), for: .normal)
        del.tintColor = .secondaryLabel
        del.translatesAutoresizingMaskIntoConstraints = false
        del.addTarget(self, action: #selector(deleteTapped), for: .touchUpInside)
        del.accessibilityLabel = "Delete"
        del.accessibilityHint = "Double tap to delete. Hold to delete continuously"
        del.isAccessibilityElement = true
        let longPress = UILongPressGestureRecognizer(target: self, action: #selector(deleteHeld(_:)))
        del.addGestureRecognizer(longPress)
        bg.addSubview(del)

        NSLayoutConstraint.activate([
            // Mic button - left side
            micButton.leadingAnchor.constraint(equalTo: bg.leadingAnchor, constant: 16),
            micButton.centerYAnchor.constraint(equalTo: bg.centerYAnchor, constant: -15),
            micButton.widthAnchor.constraint(equalToConstant: 48),
            micButton.heightAnchor.constraint(equalToConstant: 48),

            // Timer - center top
            timerLabel.centerXAnchor.constraint(equalTo: bg.centerXAnchor),
            timerLabel.topAnchor.constraint(equalTo: bg.topAnchor, constant: 16),

            // Waveform - center
            waveformView.centerXAnchor.constraint(equalTo: bg.centerXAnchor),
            waveformView.topAnchor.constraint(equalTo: timerLabel.bottomAnchor, constant: 6),
            waveformView.widthAnchor.constraint(equalToConstant: 140),
            waveformView.heightAnchor.constraint(equalToConstant: 24),

            // Progress bar - center
            progressBar.centerXAnchor.constraint(equalTo: bg.centerXAnchor),
            progressBar.topAnchor.constraint(equalTo: bg.topAnchor, constant: 45),
            progressBar.widthAnchor.constraint(equalToConstant: 120),

            // Checkmark - center
            checkmark.centerXAnchor.constraint(equalTo: bg.centerXAnchor),
            checkmark.topAnchor.constraint(equalTo: bg.topAnchor, constant: 35),
            checkmark.widthAnchor.constraint(equalToConstant: 32),
            checkmark.heightAnchor.constraint(equalToConstant: 32),

            // Status - center
            statusLabel.centerXAnchor.constraint(equalTo: bg.centerXAnchor),
            statusLabel.centerYAnchor.constraint(equalTo: bg.centerYAnchor, constant: -15),

            // Edit button - right side
            editButton.trailingAnchor.constraint(equalTo: bg.trailingAnchor, constant: -16),
            editButton.centerYAnchor.constraint(equalTo: bg.centerYAnchor, constant: -15),
            editButton.widthAnchor.constraint(equalToConstant: 40),
            editButton.heightAnchor.constraint(equalToConstant: 40),

            // Globe - bottom left
            globe.leadingAnchor.constraint(equalTo: bg.leadingAnchor, constant: 12),
            globe.bottomAnchor.constraint(equalTo: bg.bottomAnchor, constant: -10),

            // Delete - bottom right
            del.trailingAnchor.constraint(equalTo: bg.trailingAnchor, constant: -12),
            del.bottomAnchor.constraint(equalTo: bg.bottomAnchor, constant: -10),
        ])
    }

    // MARK: - WhisperKit Model Loading

    private func loadWhisperModel() {
        #if canImport(WhisperKit)
        Task {
            do {
                await MainActor.run {
                    statusLabel.text = "Loading model..."
                    statusLabel.textColor = .secondaryLabel
                }

                // Use tiny model for keyboard extension (memory constraints)
                whisperKit = try await WhisperKit(
                    model: "openai_whisper-tiny.en",
                    computeOptions: .init(
                        audioEncoderCompute: .cpuOnly,
                        textDecoderCompute: .cpuOnly
                    ),
                    verbose: false,
                    prewarm: false
                )

                isModelLoaded = true

                await MainActor.run {
                    statusLabel.text = "Tap to record"
                    statusLabel.textColor = .secondaryLabel
                }

                print("[Keyboard] WhisperKit model loaded successfully")

            } catch {
                print("[Keyboard] Failed to load WhisperKit: \(error)")
                await MainActor.run {
                    statusLabel.text = "Tap to record"
                    statusLabel.textColor = .secondaryLabel
                }
            }
        }
        #endif
    }

    // MARK: - Actions

    @objc private func micTapped() {
        if isRecording {
            stopRecording()
        } else {
            startRecording()
        }
    }

    @objc private func editTapped() {
        openApp()
    }

    @objc private func deleteTapped() {
        textDocumentProxy.deleteBackward()
    }

    private var delTimer: Timer?
    @objc private func deleteHeld(_ g: UILongPressGestureRecognizer) {
        if g.state == .began {
            delTimer = Timer.scheduledTimer(withTimeInterval: 0.08, repeats: true) { [weak self] _ in
                self?.textDocumentProxy.deleteBackward()
            }
        } else if g.state == .ended || g.state == .cancelled {
            delTimer?.invalidate()
        }
    }

    private func openApp() {
        // Include session ID in URL for editing specific session
        var urlString = "brainphart://edit"
        if let sessionId = lastSessionId {
            urlString = "brainphart://edit?session=\(sessionId)"
        }

        guard let url = URL(string: urlString) else {
            print("[Keyboard] Invalid URL: \(urlString)")
            return
        }

        print("[Keyboard] Opening URL: \(urlString)")

        // Method 1: Try UIApplication.shared (requires Full Access)
        if let app = UIApplication.value(forKeyPath: #keyPath(UIApplication.shared)) as? UIApplication {
            app.open(url, options: [:]) { success in
                print("[Keyboard] URL open result: \(success)")
            }
            return
        }

        // Method 2: Responder chain fallback
        let sel = NSSelectorFromString("openURL:")
        var r: UIResponder? = self
        while let resp = r {
            if resp.responds(to: sel) {
                resp.perform(sel, with: url)
                print("[Keyboard] Opened via responder chain")
                return
            }
            r = resp.next
        }

        print("[Keyboard] Failed to open URL - no handler found")
    }

    // MARK: - Recording

    private func requestMicPermission() {
        AVAudioApplication.requestRecordPermission { [weak self] ok in
            DispatchQueue.main.async {
                if !ok {
                    self?.statusLabel.text = "Enable Full Access"
                    self?.statusLabel.textColor = .systemOrange
                    self?.micButton.isEnabled = false
                }
            }
        }
    }

    private func startRecording() {
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()

        let session = AVAudioSession.sharedInstance()
        do {
            try session.setCategory(.playAndRecord, mode: .default, options: [.defaultToSpeaker])
            try session.setActive(true)
        } catch {
            statusLabel.text = "Audio error"
            return
        }

        audioEngine = AVAudioEngine()
        guard let engine = audioEngine else { return }

        let input = engine.inputNode
        let fmt = input.outputFormat(forBus: 0)
        sampleRate = fmt.sampleRate
        audioBuffer = []

        input.installTap(onBus: 0, bufferSize: 1024, format: fmt) { [weak self] buf, _ in
            guard let self = self, let ch = buf.floatChannelData else { return }
            let len = Int(buf.frameLength)
            let samples = Array(UnsafeBufferPointer(start: ch[0], count: len))
            self.audioBuffer.append(contentsOf: samples)
            let rms = sqrt(samples.reduce(0) { $0 + $1 * $1 } / Float(len))
            self.currentLevel = min(1, rms * 10)
        }

        do {
            try engine.start()
            isRecording = true
            recordingStartTime = Date()

            // Update UI - recording state (hide edit button from previous recording)
            micButton.backgroundColor = .systemRed.withAlphaComponent(0.9)
            micButton.setImage(UIImage(systemName: "stop.fill", withConfiguration: UIImage.SymbolConfiguration(pointSize: 16)), for: .normal)
            micButton.tintColor = .white
            statusLabel.isHidden = true
            timerLabel.isHidden = false
            waveformView.isHidden = false
            editButton.isHidden = true  // Clear previous edit button
            progressBar.isHidden = true
            checkmark.isHidden = true
            lastSessionId = nil  // Clear previous session

            startDisplayLink()
        } catch {
            statusLabel.text = "Mic error"
        }
    }

    private func stopRecording() {
        guard isRecording, let engine = audioEngine else { return }

        UIImpactFeedbackGenerator(style: .medium).impactOccurred()

        // Calculate duration before stopping
        if let startTime = recordingStartTime {
            lastRecordingDurationMs = Int(Date().timeIntervalSince(startTime) * 1000)
        }

        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        isRecording = false
        stopDisplayLink()

        // IMPORTANT: Deactivate audio session so main app can use mic
        do {
            try AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
            print("[Keyboard] Audio session deactivated")
        } catch {
            print("[Keyboard] Failed to deactivate audio session: \(error)")
        }

        // Reset button to idle
        micButton.backgroundColor = .systemGray5
        micButton.setImage(UIImage(systemName: "mic.fill", withConfiguration: UIImage.SymbolConfiguration(pointSize: 18)), for: .normal)
        micButton.tintColor = .label
        timerLabel.isHidden = true
        waveformView.isHidden = true
        statusLabel.isHidden = false

        // Show transcribing state
        statusLabel.text = "Transcribing..."
        statusLabel.textColor = .systemOrange
        progressBar.isHidden = false
        progressBar.progress = 0

        // Animate progress
        animateProgress()

        // Generate WAV and keep a copy for database
        let wavData = generateWAV()
        lastRecordedWAV = wavData
        transcribeAudio(wavData)
    }

    private func animateProgress() {
        // Fake progress animation while transcribing
        var progress: Float = 0
        Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] timer in
            guard let self = self else { timer.invalidate(); return }
            if self.isTranscribing || progress < 0.9 {
                progress = min(0.9, progress + 0.05)
                self.progressBar.setProgress(progress, animated: true)
            } else {
                timer.invalidate()
            }
        }
    }

    // MARK: - Transcription

    private func transcribeAudio(_ audioData: Data) {
        #if canImport(WhisperKit)
        guard let whisper = whisperKit else {
            // Fallback if model not loaded
            transcriptionComplete(nil, error: "Model not loaded")
            return
        }

        isTranscribing = true

        Task {
            do {
                // Write to temp file
                let tempURL = FileManager.default.temporaryDirectory
                    .appendingPathComponent(UUID().uuidString)
                    .appendingPathExtension("wav")
                try audioData.write(to: tempURL)

                defer {
                    try? FileManager.default.removeItem(at: tempURL)
                }

                // Transcribe
                let results = try await whisper.transcribe(audioPath: tempURL.path)
                let transcript = results.map { $0.text }.joined(separator: " ").trimmingCharacters(in: .whitespaces)

                await MainActor.run {
                    self.isTranscribing = false
                    self.transcriptionComplete(transcript, error: nil)
                }

            } catch {
                await MainActor.run {
                    self.isTranscribing = false
                    self.transcriptionComplete(nil, error: error.localizedDescription)
                }
            }
        }
        #else
        // WhisperKit not available - use placeholder
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
            self?.transcriptionComplete("[Voice recorded - WhisperKit not available]", error: nil)
        }
        #endif
    }

    private func transcriptionComplete(_ transcript: String?, error: String?) {
        progressBar.setProgress(1.0, animated: true)

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { [weak self] in
            guard let self = self else { return }

            self.progressBar.isHidden = true

            if let transcript = transcript, !transcript.isEmpty {
                // SUCCESS - paste into text field
                self.textDocumentProxy.insertText(transcript)

                // Save to shared storage (legacy)
                self.saveTranscript(transcript)

                // Save to shared SQLite database (single source of truth)
                if let wavData = self.lastRecordedWAV {
                    self.lastSessionId = self.saveToDatabase(
                        audioData: wavData,
                        transcript: transcript,
                        durationMs: self.lastRecordingDurationMs
                    )
                    print("[Keyboard] Saved to database: \(self.lastSessionId ?? "nil")")
                }

                // Show success state
                self.checkmark.isHidden = false
                self.statusLabel.text = "Pasted!"
                self.statusLabel.textColor = .systemGreen
                self.editButton.isHidden = false

                UINotificationFeedbackGenerator().notificationOccurred(.success)

                // Also copy to clipboard
                UIPasteboard.general.string = transcript

                // Only hide checkmark after delay - KEEP EDIT BUTTON until next recording
                DispatchQueue.main.asyncAfter(deadline: .now() + 3) { [weak self] in
                    self?.checkmark.isHidden = true
                    self?.statusLabel.text = "Edit"
                    self?.statusLabel.textColor = .systemBlue
                    // editButton stays visible until startRecording
                }

            } else {
                // FAILURE
                self.statusLabel.text = error ?? "Failed"
                self.statusLabel.textColor = .systemRed

                UINotificationFeedbackGenerator().notificationOccurred(.error)

                // Reset after delay
                DispatchQueue.main.asyncAfter(deadline: .now() + 2) { [weak self] in
                    self?.resetToIdle()
                }
            }
        }
    }

    private func resetToIdle() {
        checkmark.isHidden = true
        editButton.isHidden = true
        statusLabel.text = "Tap to record"
        statusLabel.textColor = .secondaryLabel
    }

    // MARK: - Display Link

    private func startDisplayLink() {
        displayLink = CADisplayLink(target: self, selector: #selector(tick))
        displayLink?.add(to: .main, forMode: .common)
    }

    private func stopDisplayLink() {
        displayLink?.invalidate()
        displayLink = nil
    }

    @objc private func tick() {
        if let start = recordingStartTime {
            let t = Date().timeIntervalSince(start)
            timerLabel.text = String(format: "%d:%02d", Int(t)/60, Int(t)%60)
        }
        waveformView.level = currentLevel
    }

    // MARK: - Storage

    private func saveTranscript(_ text: String) {
        guard let d = UserDefaults(suiteName: appGroupID) else { return }
        d.set(text, forKey: "latestTranscript")
        d.set(Date().timeIntervalSince1970, forKey: "transcriptTimestamp")
        d.synchronize()
    }

    /// Save to shared SQLite database (single source of truth)
    private func saveToDatabase(audioData: Data, transcript: String, durationMs: Int) -> String? {
        guard let containerURL = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroupID) else {
            print("[Keyboard] ERROR: App Groups container not available")
            return nil
        }

        let dbPath = containerURL.appendingPathComponent("voicerecorder.db").path
        var db: OpaquePointer?

        guard sqlite3_open(dbPath, &db) == SQLITE_OK else {
            print("[Keyboard] ERROR: Failed to open database")
            return nil
        }

        defer { sqlite3_close(db) }

        // Create tables if they don't exist
        let createSQL = """
            CREATE TABLE IF NOT EXISTS sessions (
                id TEXT PRIMARY KEY,
                created_at INTEGER NOT NULL,
                completed_at INTEGER,
                status TEXT DEFAULT 'recording',
                transcript TEXT,
                source TEXT DEFAULT 'app'
            );
            CREATE TABLE IF NOT EXISTS chunks (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                session_id TEXT NOT NULL,
                chunk_number INTEGER NOT NULL,
                audio_blob BLOB NOT NULL,
                duration_ms INTEGER,
                created_at INTEGER NOT NULL
            );
        """
        sqlite3_exec(db, createSQL, nil, nil, nil)

        let sessionId = UUID().uuidString
        let now = Int64(Date().timeIntervalSince1970)

        // Insert session
        let sessionSQL = "INSERT INTO sessions (id, created_at, completed_at, status, transcript, source) VALUES (?, ?, ?, 'completed', ?, 'keyboard');"
        var statement: OpaquePointer?

        if sqlite3_prepare_v2(db, sessionSQL, -1, &statement, nil) == SQLITE_OK {
            sqlite3_bind_text(statement, 1, (sessionId as NSString).utf8String, -1, nil)
            sqlite3_bind_int64(statement, 2, now)
            sqlite3_bind_int64(statement, 3, now)
            sqlite3_bind_text(statement, 4, (transcript as NSString).utf8String, -1, nil)

            if sqlite3_step(statement) != SQLITE_DONE {
                print("[Keyboard] ERROR: Failed to insert session")
            }
        }
        sqlite3_finalize(statement)

        // Insert audio chunk
        let chunkSQL = "INSERT INTO chunks (session_id, chunk_number, audio_blob, duration_ms, created_at) VALUES (?, 0, ?, ?, ?);"

        if sqlite3_prepare_v2(db, chunkSQL, -1, &statement, nil) == SQLITE_OK {
            sqlite3_bind_text(statement, 1, (sessionId as NSString).utf8String, -1, nil)

            audioData.withUnsafeBytes { ptr in
                sqlite3_bind_blob(statement, 2, ptr.baseAddress, Int32(audioData.count), nil)
            }

            sqlite3_bind_int(statement, 3, Int32(durationMs))
            sqlite3_bind_int64(statement, 4, now)

            if sqlite3_step(statement) != SQLITE_DONE {
                print("[Keyboard] ERROR: Failed to insert chunk")
            }
        }
        sqlite3_finalize(statement)

        print("[Keyboard] Saved session \(sessionId) with \(audioData.count) bytes audio")
        return sessionId
    }

    // MARK: - WAV Generation

    private func generateWAV() -> Data {
        let samples = audioBuffer.map { Int16(max(-1, min(1, $0)) * 32767) }
        var d = Data()
        d.append("RIFF".data(using: .ascii)!)
        d.append(withUnsafeBytes(of: UInt32(36 + samples.count * 2).littleEndian) { Data($0) })
        d.append("WAVE".data(using: .ascii)!)
        d.append("fmt ".data(using: .ascii)!)
        d.append(withUnsafeBytes(of: UInt32(16).littleEndian) { Data($0) })
        d.append(withUnsafeBytes(of: UInt16(1).littleEndian) { Data($0) })
        d.append(withUnsafeBytes(of: Int16(1).littleEndian) { Data($0) })
        d.append(withUnsafeBytes(of: Int32(sampleRate).littleEndian) { Data($0) })
        d.append(withUnsafeBytes(of: Int32(sampleRate * 2).littleEndian) { Data($0) })
        d.append(withUnsafeBytes(of: Int16(2).littleEndian) { Data($0) })
        d.append(withUnsafeBytes(of: Int16(16).littleEndian) { Data($0) })
        d.append("data".data(using: .ascii)!)
        d.append(withUnsafeBytes(of: UInt32(samples.count * 2).littleEndian) { Data($0) })
        for s in samples { d.append(withUnsafeBytes(of: s.littleEndian) { Data($0) }) }
        return d
    }
}

// MARK: - Simple Waveform View

class SimpleWaveform: UIView {
    var level: Float = 0 { didSet { setNeedsDisplay() } }

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .clear
    }
    required init?(coder: NSCoder) { fatalError() }

    override func draw(_ rect: CGRect) {
        guard let ctx = UIGraphicsGetCurrentContext() else { return }
        let n = 12, w: CGFloat = 3, sp: CGFloat = 4
        let total = CGFloat(n) * (w + sp) - sp
        let x0 = (rect.width - total) / 2

        for i in 0..<n {
            let x = x0 + CGFloat(i) * (w + sp)
            let phase = sin(Double(i) * 0.5 + Double(level) * 8)
            let hf = 0.2 + CGFloat(level) * 0.8 * CGFloat(phase * 0.5 + 0.5)
            let h = max(3, rect.height * hf)
            let y = (rect.height - h) / 2
            ctx.setFillColor(UIColor.systemGray.cgColor)
            ctx.fill(CGRect(x: x, y: y, width: w, height: h))
        }
    }
}
