//
//  Settings.swift
//  VoiceRecorder
//
//  Observable settings model backed by UserDefaults.
//  Stores hotkey configuration, model selection, and auto-paste preferences.
//

import AppKit
import Foundation

// MARK: - Recording Mode

enum RecordingMode: String, CaseIterable, Identifiable {
    case toggle = "toggle"
    case pushToTalk = "pushToTalk"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .toggle: return "Toggle"
        case .pushToTalk: return "Push to Talk"
        }
    }
}

// MARK: - App Settings

@MainActor
@Observable
final class AppSettings {

    // MARK: - UserDefaults Keys

    private enum Keys {
        static let hotkeyKeyCode = "hotkeyKeyCode"
        static let hotkeyModifiers = "hotkeyModifiers"
        static let selectedModelPath = "selectedModelPath"
        static let autoPasteEnabled = "autoPasteEnabled"
        static let restoreClipboard = "restoreClipboard"
        static let recordingMode = "recordingMode"
    }

    // MARK: - Defaults

    /// Carbon key code for 'R' key.
    private static let defaultKeyCode: UInt32 = 15

    /// Option + Shift modifier flags.
    private static let defaultModifiers: UInt32 = UInt32(
        NSEvent.ModifierFlags.option.rawValue | NSEvent.ModifierFlags.shift.rawValue
    )

    // MARK: - Stored Properties

    var hotkeyKeyCode: UInt32 {
        didSet { UserDefaults.standard.set(hotkeyKeyCode, forKey: Keys.hotkeyKeyCode) }
    }

    var hotkeyModifiers: UInt32 {
        didSet { UserDefaults.standard.set(hotkeyModifiers, forKey: Keys.hotkeyModifiers) }
    }

    var selectedModelPath: String {
        didSet { UserDefaults.standard.set(selectedModelPath, forKey: Keys.selectedModelPath) }
    }

    var autoPasteEnabled: Bool {
        didSet { UserDefaults.standard.set(autoPasteEnabled, forKey: Keys.autoPasteEnabled) }
    }

    var restoreClipboard: Bool {
        didSet { UserDefaults.standard.set(restoreClipboard, forKey: Keys.restoreClipboard) }
    }

    var recordingMode: RecordingMode {
        didSet { UserDefaults.standard.set(recordingMode.rawValue, forKey: Keys.recordingMode) }
    }

    // MARK: - Init

    init() {
        let defaults = UserDefaults.standard

        // Register defaults for first launch.
        defaults.register(defaults: [
            Keys.hotkeyKeyCode: AppSettings.defaultKeyCode,
            Keys.hotkeyModifiers: AppSettings.defaultModifiers,
            Keys.selectedModelPath: "",
            Keys.autoPasteEnabled: true,
            Keys.restoreClipboard: true,
            Keys.recordingMode: RecordingMode.toggle.rawValue,
        ])

        self.hotkeyKeyCode = UInt32(defaults.integer(forKey: Keys.hotkeyKeyCode))
        self.hotkeyModifiers = UInt32(defaults.integer(forKey: Keys.hotkeyModifiers))
        self.selectedModelPath = defaults.string(forKey: Keys.selectedModelPath) ?? ""
        self.autoPasteEnabled = defaults.bool(forKey: Keys.autoPasteEnabled)
        self.restoreClipboard = defaults.bool(forKey: Keys.restoreClipboard)

        let modeRaw = defaults.string(forKey: Keys.recordingMode) ?? RecordingMode.toggle.rawValue
        self.recordingMode = RecordingMode(rawValue: modeRaw) ?? .toggle
    }

    // MARK: - Hotkey Display

    /// Human-readable representation of the current hotkey binding.
    var hotkeyDisplayString: String {
        var parts: [String] = []
        let mods = NSEvent.ModifierFlags(rawValue: UInt(hotkeyModifiers))

        if mods.contains(.control) { parts.append("\u{2303}") }   // ⌃
        if mods.contains(.option)  { parts.append("\u{2325}") }   // ⌥
        if mods.contains(.shift)   { parts.append("\u{21E7}") }   // ⇧
        if mods.contains(.command) { parts.append("\u{2318}") }   // ⌘

        parts.append(keyCodeToString(hotkeyKeyCode))
        return parts.joined()
    }

    /// Convert a Carbon virtual key code to a display string.
    private func keyCodeToString(_ keyCode: UInt32) -> String {
        let mapping: [UInt32: String] = [
            0: "A", 1: "S", 2: "D", 3: "F", 4: "H", 5: "G", 6: "Z", 7: "X",
            8: "C", 9: "V", 11: "B", 12: "Q", 13: "W", 14: "E", 15: "R",
            16: "Y", 17: "T", 31: "O", 32: "U", 34: "I", 35: "P", 37: "L",
            38: "J", 40: "K", 45: "N", 46: "M",
            18: "1", 19: "2", 20: "3", 21: "4", 22: "6", 23: "5",
            25: "9", 26: "7", 28: "8", 29: "0",
            49: "Space", 36: "Return", 48: "Tab", 51: "Delete", 53: "Escape",
        ]
        return mapping[keyCode] ?? "Key\(keyCode)"
    }

    // MARK: - Available Models

    /// Scans common locations for Whisper .bin model files.
    /// Returns a list of (display name, full path) pairs.
    func availableModels() -> [(name: String, path: String)] {
        var found: [(name: String, path: String)] = []
        var seen = Set<String>()

        let fm = FileManager.default

        // Collect candidate directories to scan.
        var dirs: [URL] = []

        // Bundle Resources/models/
        if let resourceURL = Bundle.main.resourceURL {
            dirs.append(resourceURL.appendingPathComponent("models"))
            dirs.append(resourceURL)
        }

        // Development: project Resources/models/ (walk up from executable)
        let execURL = URL(fileURLWithPath: ProcessInfo.processInfo.arguments[0])
            .resolvingSymlinksInPath()
        var dir = execURL.deletingLastPathComponent()
        for _ in 0..<6 {
            dirs.append(dir.appendingPathComponent("Resources/models"))
            dir = dir.deletingLastPathComponent()
        }

        // Current working directory
        let cwd = URL(fileURLWithPath: fm.currentDirectoryPath)
        dirs.append(cwd.appendingPathComponent("Resources/models"))

        // Scan each directory for .bin files
        for searchDir in dirs {
            guard let contents = try? fm.contentsOfDirectory(
                at: searchDir,
                includingPropertiesForKeys: nil,
                options: [.skipsHiddenFiles]
            ) else { continue }

            for fileURL in contents where fileURL.pathExtension == "bin" {
                let path = fileURL.path
                guard !seen.contains(path) else { continue }
                seen.insert(path)

                let name = fileURL.deletingPathExtension().lastPathComponent
                found.append((name: name, path: path))
            }
        }

        // Sort by name for consistent display.
        found.sort { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        return found
    }
}
