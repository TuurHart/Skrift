import Foundation

/// Canonical on-disk locations for the native desktop app. Config (names.json,
/// settings) lives in `~/Library/Application Support/Skrift/` — the same place the
/// Electron/Python app used, so the user's existing names DB carries over. Per-file
/// working folders stay in `~/Documents/Voice Transcription Pipeline Audio Output/`
/// to match the current layout (plan §3 — keep the on-disk layout identical).
enum AppPaths {
    static var appSupportDirectory: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let dir = base.appendingPathComponent("Skrift", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    static var namesFile: URL { appSupportDirectory.appendingPathComponent("names.json") }
    static var settingsFile: URL { appSupportDirectory.appendingPathComponent("user_settings.json") }

    static var audioOutputDirectory: URL {
        let base = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        let dir = base.appendingPathComponent("Voice Transcription Pipeline Audio Output", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }
}
