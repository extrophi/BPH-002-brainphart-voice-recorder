import SwiftUI

// MARK: - Settings View

struct SettingsView: View {
    @EnvironmentObject var appState: AppState

    @State private var selectedModel: String = "base"
    @State private var dictionaryWords: [String] = []
    @State private var newWord: String = ""
    @State private var showAddWord = false

    var body: some View {
        TabView {
            // General Settings
            GeneralSettingsTab(selectedModel: $selectedModel)
                .tabItem {
                    Label("General", systemImage: "gear")
                }

            // Dictionary Settings
            DictionarySettingsTab(
                words: $dictionaryWords,
                newWord: $newWord,
                showAddWord: $showAddWord
            )
                .tabItem {
                    Label("Dictionary", systemImage: "textformat.abc")
                }

            // About
            AboutTab()
                .tabItem {
                    Label("About", systemImage: "info.circle")
                }
        }
        .frame(width: 450, height: 350)
        .onAppear {
            loadSettings()
        }
    }

    private func loadSettings() {
        selectedModel = DatabaseManager.shared.getSetting(key: "whisper_model") ?? "base"
        dictionaryWords = DatabaseManager.shared.getAllWords()
    }
}

// MARK: - General Settings Tab

struct GeneralSettingsTab: View {
    @Binding var selectedModel: String

    let models = [
        ("tiny", "75MB", "Fastest, ~85% accuracy"),
        ("base", "142MB", "Default, ~88% accuracy"),
        ("small", "466MB", "Better, ~91% accuracy"),
        ("medium", "1.5GB", "High, ~94% accuracy"),
        ("large", "3GB", "Best, ~96% accuracy")
    ]

    var body: some View {
        Form {
            Section("Whisper Model") {
                Picker("Model", selection: $selectedModel) {
                    ForEach(models, id: \.0) { model in
                        HStack {
                            Text(model.0.capitalized)
                            Spacer()
                            Text(model.1)
                                .foregroundColor(.secondary)
                        }
                        .tag(model.0)
                    }
                }
                .pickerStyle(.inline)
                .onChange(of: selectedModel) { newValue in
                    DatabaseManager.shared.setSetting(key: "whisper_model", value: newValue)
                    Task {
                        try? await TranscriptionManager.shared.switchModel(to: newValue)
                    }
                }

                Text("Larger models are more accurate but slower")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Section("Model Location") {
                #if os(macOS)
                let modelPath = "~/brainphart/models/"
                #else
                let modelPath = "Documents/models/"
                #endif

                Text(modelPath)
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundColor(.secondary)

                #if os(macOS)
                Button("Open Folder") {
                    let path = FileManager.default.homeDirectoryForCurrentUser
                        .appendingPathComponent("brainphart/models")
                    NSWorkspace.shared.open(path)
                }
                #endif
            }

            Section("Hotkey") {
                HStack {
                    Text("Toggle Recording")
                    Spacer()
                    Text("Ctrl + Shift + Space")
                        .font(.system(size: 12, design: .monospaced))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color.primary.opacity(0.1))
                        .cornerRadius(4)
                }
            }
        }
        .padding()
    }
}

// MARK: - Dictionary Settings Tab

struct DictionarySettingsTab: View {
    @Binding var words: [String]
    @Binding var newWord: String
    @Binding var showAddWord: Bool

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Personal Dictionary")
                    .font(.headline)

                Spacer()

                Button(action: { showAddWord = true }) {
                    Image(systemName: "plus")
                }
                .buttonStyle(.plain)
            }
            .padding()

            Divider()

            // Word list
            if words.isEmpty {
                Spacer()
                VStack(spacing: 8) {
                    Image(systemName: "textformat.abc")
                        .font(.system(size: 32))
                        .foregroundColor(.secondary)
                    Text("No custom words yet")
                        .foregroundColor(.secondary)
                    Text("Add words that Whisper often misspells")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                Spacer()
            } else {
                List {
                    ForEach(words, id: \.self) { word in
                        HStack {
                            Text(word)
                            Spacer()
                            Button(action: { removeWord(word) }) {
                                Image(systemName: "trash")
                                    .foregroundColor(.red)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
        }
        .sheet(isPresented: $showAddWord) {
            AddWordSheet(newWord: $newWord, onAdd: addWord, onCancel: { showAddWord = false })
        }
    }

    private func addWord() {
        guard !newWord.isEmpty else { return }
        DatabaseManager.shared.addWord(newWord)
        words = DatabaseManager.shared.getAllWords()
        newWord = ""
        showAddWord = false
    }

    private func removeWord(_ word: String) {
        DatabaseManager.shared.removeWord(word)
        words = DatabaseManager.shared.getAllWords()
    }
}

// MARK: - Add Word Sheet

struct AddWordSheet: View {
    @Binding var newWord: String
    let onAdd: () -> Void
    let onCancel: () -> Void

    var body: some View {
        VStack(spacing: 16) {
            Text("Add Custom Word")
                .font(.headline)

            TextField("Word or phrase", text: $newWord)
                .textFieldStyle(.roundedBorder)
                .frame(width: 200)

            HStack {
                Button("Cancel", action: onCancel)
                    .buttonStyle(.bordered)

                Button("Add", action: onAdd)
                    .buttonStyle(.borderedProminent)
                    .disabled(newWord.isEmpty)
            }
        }
        .padding()
        .frame(width: 300, height: 150)
    }
}

// MARK: - About Tab

struct AboutTab: View {
    var body: some View {
        VStack(spacing: 16) {
            // Logo placeholder
            Image(systemName: "waveform.circle.fill")
                .font(.system(size: 64))
                .foregroundColor(.accentColor)

            Text("BrainPhart Voice")
                .font(.title2)
                .fontWeight(.semibold)

            Text("Version 1.0.0")
                .foregroundColor(.secondary)

            Divider()
                .frame(width: 200)

            VStack(spacing: 4) {
                Text("Privacy-first voice recorder")
                Text("with local Whisper transcription")
            }
            .font(.caption)
            .foregroundColor(.secondary)
            .multilineTextAlignment(.center)

            Spacer()

            VStack(spacing: 4) {
                Text("No cloud. No subscription.")
                Text("Your data stays on your device.")
            }
            .font(.caption)
            .foregroundColor(.secondary)
        }
        .padding()
    }
}
