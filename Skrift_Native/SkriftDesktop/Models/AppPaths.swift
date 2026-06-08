import Foundation

/// Canonical on-disk locations for the native desktop app. Config (names.json,
/// settings) lives in `~/Library/Application Support/Skrift/` — the same place the
/// Electron/Python app used, so the user's existing names DB carries over. Per-file
/// working folders stay in `~/Documents/Voice Transcription Pipeline Audio Output/`
/// to match the current layout (plan §3 — keep the on-disk layout identical).
enum AppPaths {
    // Dev/prod separation: the Debug ("Skrift Dev") build keeps ALL its on-disk data
    // in a separate, suffixed location so dev iteration never touches the production
    // app's names DB / settings / audio output. Release ("Skrift") keeps the original
    // paths (inheriting the existing names DB).
    #if DEBUG
    private static let dataSuffix = " Dev"
    #else
    private static let dataSuffix = ""
    #endif

    static var appSupportDirectory: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let dir = base.appendingPathComponent("Skrift\(dataSuffix)", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    static var namesFile: URL { appSupportDirectory.appendingPathComponent("names.json") }
    static var settingsFile: URL { appSupportDirectory.appendingPathComponent("user_settings.json") }

    /// SwiftData store — explicit path inside appSupportDirectory so it's isolated
    /// per build (the default store location is NOT bundle-id-namespaced for a
    /// non-sandboxed macOS app, which would share dev + prod data).
    static var storeFile: URL { appSupportDirectory.appendingPathComponent("skrift.store") }

    static var audioOutputDirectory: URL {
        let base = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        let dir = base.appendingPathComponent("Voice Transcription Pipeline Audio Output\(dataSuffix)", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }
}
