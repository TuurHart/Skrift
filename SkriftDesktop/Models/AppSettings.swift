import Foundation

/// User-configurable settings, persisted to `AppPaths.settingsFile`. Mirrors the
/// subset of `backend/config/settings.py` the native app needs. LLM prompt strings
/// are intentionally NOT baked here yet — they're ported exactly in Phase 4
/// (enhancement), so this stays the single skeleton without guessed copy.
struct AppSettings: Codable, Equatable, Sendable {
    // Export → Obsidian vault
    var noteFolder: String = ""          // vault root
    var audioFolder: String = ""         // vault subfolder for voice memos
    var attachmentsFolder: String = ""   // vault subfolder for images (falls back to root)
    var authorName: String = ""

    // Enhancement model (shipped default = the tuned 8bit; downloaded from HF on first run)
    var enhancementModelRepo: String = "mlx-community/gemma-4-e4b-it-8bit"

    // Transcription preprocessing (ffmpeg/AVFoundation)
    var noiseReductionDB: Int = -20      // afftdn noise floor; 0 = off
    var highpassFreqHz: Int = 80         // high-pass cutoff; 0 = off

    static let `default` = AppSettings()
}

/// Codable load/save for `AppSettings` at `AppPaths.settingsFile`. Backend remains
/// the single source of truth conceptually; this is the native persistence.
final class SettingsStore {
    static let shared = SettingsStore()

    private let fileURL: URL
    private let encoder: JSONEncoder
    private let decoder = JSONDecoder()

    init(fileURL: URL = AppPaths.settingsFile) {
        self.fileURL = fileURL
        let e = JSONEncoder()
        e.outputFormatting = [.prettyPrinted, .sortedKeys]
        self.encoder = e
    }

    func load() -> AppSettings {
        guard let data = try? Data(contentsOf: fileURL),
              let parsed = try? decoder.decode(AppSettings.self, from: data) else {
            return .default
        }
        return parsed
    }

    @discardableResult
    func save(_ settings: AppSettings) -> AppSettings {
        if let encoded = try? encoder.encode(settings) {
            try? encoded.write(to: fileURL)
        }
        return settings
    }
}
