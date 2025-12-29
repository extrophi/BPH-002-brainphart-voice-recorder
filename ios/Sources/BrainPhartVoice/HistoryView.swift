import SwiftUI

// MARK: - History Sidebar

struct HistoryView: View {
    let recordings: [RecordingItem]
    let selectedId: String?
    let onSelect: (RecordingItem) -> Void
    let onDelete: (RecordingItem) -> Void
    let onRefresh: () -> Void

    @State private var searchText = ""

    var filteredRecordings: [RecordingItem] {
        if searchText.isEmpty {
            return recordings
        }
        return recordings.filter { recording in
            recording.transcript.localizedCaseInsensitiveContains(searchText) ||
            recording.dateString.localizedCaseInsensitiveContains(searchText)
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("HISTORY")
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundColor(.secondary)

                Spacer()

                Button(action: onRefresh) {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 11))
                }
                .buttonStyle(.plain)
                .help("Refresh")
            }
            .padding(.horizontal)
            .padding(.top, 12)
            .padding(.bottom, 8)

            // Search
            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundColor(.secondary)
                    .font(.system(size: 12))

                TextField("Search...", text: $searchText)
                    .textFieldStyle(.plain)
                    .font(.system(size: 12))

                if !searchText.isEmpty {
                    Button(action: { searchText = "" }) {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(.secondary)
                            .font(.system(size: 11))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(8)
            .background(Color.primary.opacity(0.05))
            .cornerRadius(6)
            .padding(.horizontal, 12)
            .padding(.bottom, 8)

            Divider()

            // Recording list
            if filteredRecordings.isEmpty {
                Spacer()
                VStack(spacing: 8) {
                    Image(systemName: searchText.isEmpty ? "waveform" : "magnifyingglass")
                        .font(.system(size: 32))
                        .foregroundColor(.secondary)
                    Text(searchText.isEmpty ? "No recordings yet" : "No results")
                        .foregroundColor(.secondary)
                }
                Spacer()
            } else {
                ScrollView {
                    LazyVStack(spacing: 8) {
                        ForEach(filteredRecordings) { recording in
                            HistoryCard(
                                recording: recording,
                                isSelected: recording.id == selectedId,
                                onSelect: { onSelect(recording) },
                                onDelete: { onDelete(recording) }
                            )
                        }
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                }
            }
        }
        #if os(macOS)
        .background(Color(NSColor.controlBackgroundColor))
        #endif
    }
}

// MARK: - History Card

struct HistoryCard: View {
    let recording: RecordingItem
    let isSelected: Bool
    let onSelect: () -> Void
    let onDelete: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                // Status indicator
                Circle()
                    .fill(statusColor)
                    .frame(width: 6, height: 6)

                Text(recording.dateString)
                    .font(.caption)
                    .foregroundColor(.secondary)

                Spacer()

                // Duration
                Text(recording.durationString)
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundColor(.secondary)

                // Processing indicator
                if recording.isProcessing {
                    ProgressView()
                        .scaleEffect(0.5)
                }
            }

            Text(recording.title)
                .font(.system(size: 12))
                .lineLimit(2)
                .foregroundColor(.primary)

            // Status label
            if recording.hasTranscript {
                Label("Transcribed", systemImage: "checkmark.circle.fill")
                    .font(.system(size: 9))
                    .foregroundColor(.green)
            } else if recording.isProcessing {
                Label("Transcribing...", systemImage: "waveform")
                    .font(.system(size: 9))
                    .foregroundColor(.orange)
            }
        }
        .padding(10)
        .background(isSelected ? Color.accentColor.opacity(0.15) : Color.primary.opacity(0.03))
        .cornerRadius(8)
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(isSelected ? Color.accentColor : Color.clear, lineWidth: 1.5)
        )
        .contentShape(Rectangle())
        .onTapGesture {
            onSelect()
        }
        .contextMenu {
            Button(role: .destructive, action: onDelete) {
                Label("Delete", systemImage: "trash")
            }
        }
    }

    private var statusColor: Color {
        if recording.hasTranscript {
            return .green
        } else if recording.isProcessing {
            return .orange
        } else {
            return .gray.opacity(0.4)
        }
    }
}
