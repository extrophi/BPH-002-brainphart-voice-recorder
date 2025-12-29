import SwiftUI

// MARK: - Transcript View

struct TranscriptView: View {
    let recording: RecordingItem
    @Binding var transcript: String
    let onSave: () -> Void

    @State private var showVersions = false
    @State private var showCopied = false
    @State private var versions: [TranscriptVersion] = []

    var body: some View {
        VStack(spacing: 0) {
            // Toolbar
            TranscriptToolbar(
                recording: recording,
                transcript: transcript,
                showCopied: $showCopied,
                showVersions: $showVersions,
                onCopy: copyToClipboard,
                onSave: onSave
            )

            Divider()

            // Text editor with spell check
            TranscriptEditor(text: $transcript, recordingId: recording.id)
                .frame(maxWidth: .infinity, maxHeight: .infinity)

            Divider()

            // Stats bar
            StatsBar(
                wordCount: wordCount(transcript),
                versionCount: versions.count,
                isProcessing: recording.isProcessing
            )
        }
        .onAppear {
            loadVersions()
        }
        .onChange(of: recording.id) { _ in
            loadVersions()
        }
        .sheet(isPresented: $showVersions) {
            VersionHistorySheet(
                versions: versions,
                onRevert: { version in
                    transcript = version.content
                    onSave()
                    showVersions = false
                }
            )
        }
    }

    private func loadVersions() {
        versions = DatabaseManager.shared.getAllVersions(sessionId: recording.id)
    }

    private func wordCount(_ text: String) -> Int {
        text.split(whereSeparator: { $0.isWhitespace || $0.isNewline }).count
    }

    private func copyToClipboard() {
        #if os(macOS)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(transcript, forType: .string)
        #else
        UIPasteboard.general.string = transcript
        #endif

        showCopied = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            showCopied = false
        }
    }
}

// MARK: - Transcript Toolbar

struct TranscriptToolbar: View {
    let recording: RecordingItem
    let transcript: String
    @Binding var showCopied: Bool
    @Binding var showVersions: Bool
    let onCopy: () -> Void
    let onSave: () -> Void

    var body: some View {
        HStack {
            // Date and duration
            VStack(alignment: .leading, spacing: 2) {
                Text(recording.dateString)
                    .font(.headline)
                Text(recording.durationString)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Spacer()

            // Version history button
            Button(action: { showVersions = true }) {
                HStack(spacing: 4) {
                    Image(systemName: "clock.arrow.circlepath")
                    Text("History")
                }
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(Color.primary.opacity(0.06))
            .cornerRadius(4)

            // Copy button
            Button(action: onCopy) {
                HStack(spacing: 4) {
                    Image(systemName: showCopied ? "checkmark" : "doc.on.doc")
                    Text(showCopied ? "Copied" : "Copy")
                }
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(Color.primary.opacity(0.06))
            .cornerRadius(4)

            // Save button
            Button(action: onSave) {
                HStack(spacing: 4) {
                    Image(systemName: "square.and.arrow.down")
                    Text("Save")
                }
            }
            .keyboardShortcut("s", modifiers: .command)
            .buttonStyle(.plain)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(Color.accentColor.opacity(0.15))
            .cornerRadius(4)
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
        #if os(macOS)
        .background(Color(NSColor.controlBackgroundColor))
        #endif
    }
}

// MARK: - Transcript Editor

struct TranscriptEditor: View {
    @Binding var text: String
    let recordingId: String

    var body: some View {
        #if os(macOS)
        // macOS: Use NSTextView wrapper for spell check
        SpellCheckTextEditor(text: $text)
            .id(recordingId)
        #else
        // iOS: Standard TextEditor
        TextEditor(text: $text)
            .font(.system(size: 16))
            .padding()
            .id(recordingId)
        #endif
    }
}

// MARK: - Spell Check Text Editor (macOS)

#if os(macOS)
import AppKit

struct SpellCheckTextEditor: NSViewRepresentable {
    @Binding var text: String

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSTextView.scrollableTextView()
        let textView = scrollView.documentView as! NSTextView

        // Enable spell check (no predictive)
        textView.isContinuousSpellCheckingEnabled = true
        textView.isGrammarCheckingEnabled = true
        textView.isAutomaticSpellingCorrectionEnabled = false
        textView.isAutomaticTextCompletionEnabled = false

        // Font
        textView.font = NSFont.systemFont(ofSize: 16)

        // Delegate
        textView.delegate = context.coordinator

        return scrollView
    }

    func updateNSView(_ nsView: NSScrollView, context: Context) {
        let textView = nsView.documentView as! NSTextView
        if textView.string != text {
            textView.string = text
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    class Coordinator: NSObject, NSTextViewDelegate {
        var parent: SpellCheckTextEditor

        init(_ parent: SpellCheckTextEditor) {
            self.parent = parent
        }

        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            parent.text = textView.string
        }
    }
}
#endif

// MARK: - Stats Bar

struct StatsBar: View {
    let wordCount: Int
    let versionCount: Int
    let isProcessing: Bool

    var body: some View {
        HStack {
            // Word count
            Label("\(wordCount) words", systemImage: "doc.text")
                .font(.system(size: 11))
                .foregroundColor(.secondary)

            Spacer()

            // Version count
            if versionCount > 0 {
                Label("v\(versionCount)", systemImage: "clock.arrow.circlepath")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
            }

            // Processing indicator
            if isProcessing {
                HStack(spacing: 4) {
                    ProgressView()
                        .scaleEffect(0.5)
                    Text("Transcribing...")
                        .font(.system(size: 11))
                        .foregroundColor(.orange)
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        #if os(macOS)
        .background(Color(NSColor.controlBackgroundColor))
        #endif
    }
}

// MARK: - Version History Sheet

struct VersionHistorySheet: View {
    let versions: [TranscriptVersion]
    let onRevert: (TranscriptVersion) -> Void

    @Environment(\.dismiss) var dismiss

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Version History")
                    .font(.headline)

                Spacer()

                Button(action: { dismiss() }) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
            }
            .padding()

            Divider()

            // Version list
            if versions.isEmpty {
                Spacer()
                Text("No version history")
                    .foregroundColor(.secondary)
                Spacer()
            } else {
                List(versions.reversed(), id: \.id) { version in
                    VersionRow(version: version, onRevert: onRevert)
                }
            }
        }
        .frame(minWidth: 400, minHeight: 300)
    }
}

struct VersionRow: View {
    let version: TranscriptVersion
    let onRevert: (TranscriptVersion) -> Void

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text("v\(version.versionNum)")
                        .font(.system(size: 12, weight: .semibold, design: .monospaced))

                    Text(version.versionType)
                        .font(.system(size: 10))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(typeColor.opacity(0.2))
                        .foregroundColor(typeColor)
                        .cornerRadius(4)
                }

                Text(version.dateString)
                    .font(.caption)
                    .foregroundColor(.secondary)

                Text(version.content.prefix(100) + (version.content.count > 100 ? "..." : ""))
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
                    .lineLimit(2)
            }

            Spacer()

            Button("Revert") {
                onRevert(version)
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
        }
        .padding(.vertical, 4)
    }

    private var typeColor: Color {
        switch version.versionType {
        case "original":
            return .blue
        case "user_edit":
            return .green
        default:
            return .gray
        }
    }
}

// MARK: - Empty Transcript View

struct EmptyTranscriptView: View {
    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "waveform")
                .font(.system(size: 48))
                .foregroundColor(.secondary)

            Text("Select a recording")
                .font(.headline)
                .foregroundColor(.secondary)

            Text("Or press Record to create one")
                .font(.subheadline)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
