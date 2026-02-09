//
//  SettingsView.swift
//  VoiceRecorder
//
//  SwiftUI Settings view with hotkey display, model picker,
//  auto-paste toggles, and about section.
//

import SwiftUI

struct SettingsView: View {
    @Environment(AppSettings.self) private var settings

    var body: some View {
        @Bindable var settings = settings

        Form {
            hotkeySection
            modelSection
            autoPasteSection
            aboutSection
        }
        .formStyle(.grouped)
        .frame(width: 450, height: 400)
    }

    // MARK: - Hotkey Section

    private var hotkeySection: some View {
        Section("Hotkey") {
            LabeledContent("Current Binding") {
                Text(settings.hotkeyDisplayString)
                    .font(.system(.title2, design: .rounded, weight: .medium))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(.quaternary, in: RoundedRectangle(cornerRadius: 6))
            }

            Picker("Recording Mode", selection: Bindable(settings).recordingMode) {
                ForEach(RecordingMode.allCases) { mode in
                    Text(mode.displayName).tag(mode)
                }
            }

            Text("Restart the app to apply hotkey changes.")
                .font(.callout)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Model Section

    private var modelSection: some View {
        Section("Whisper Model") {
            let models = settings.availableModels()

            if models.isEmpty {
                LabeledContent("Model") {
                    Text("No .bin models found")
                        .foregroundStyle(.secondary)
                }
                Text("Place whisper .bin model files in Resources/models/")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            } else {
                Picker("Model", selection: Bindable(settings).selectedModelPath) {
                    Text("Auto-detect")
                        .tag("")
                    ForEach(models, id: \.path) { model in
                        Text(model.name)
                            .tag(model.path)
                    }
                }

                if !settings.selectedModelPath.isEmpty {
                    Text(settings.selectedModelPath)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }
            }
        }
    }

    // MARK: - Auto-Paste Section

    private var autoPasteSection: some View {
        Section("Auto-Paste") {
            Toggle("Auto-paste transcriptions", isOn: Bindable(settings).autoPasteEnabled)

            if settings.autoPasteEnabled {
                Toggle("Restore clipboard after paste", isOn: Bindable(settings).restoreClipboard)
            }

            Text("When enabled, transcriptions are automatically pasted at your cursor position. Requires Accessibility permission.")
                .font(.callout)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - About Section

    private var aboutSection: some View {
        Section("About") {
            LabeledContent("App") {
                Text("BrainPhart Voice")
            }
            LabeledContent("Version") {
                Text(appVersion)
            }
        }
    }

    private var appVersion: String {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "—"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "—"
        return "\(version) (\(build))"
    }
}
