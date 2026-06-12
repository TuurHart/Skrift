import Foundation

/// User-configurable settings, persisted to `AppPaths.settingsFile`. Mirrors the
/// subset of `backend/config/settings.py` the native app needs.
struct AppSettings: Codable, Equatable, Sendable {
    // Export → Obsidian vault
    var noteFolder: String = ""          // vault root
    var audioFolder: String = ""         // vault subfolder for voice memos
    var attachmentsFolder: String = ""   // vault subfolder for images (falls back to root)
    var authorName: String = ""

    // Enhancement model (shipped default = the tuned 8bit; downloaded from HF on first run)
    var enhancementModelRepo: String = "mlx-community/gemma-4-e4b-it-8bit"
    var prompts: Prompts = .init()

    // Transcription preprocessing (native AVFoundation): high-pass + peak normalize →
    // 16 kHz mono before ASR. (afftdn-style noise reduction has no faithful native
    // equivalent, so it's intentionally not offered — see A4.)
    var highpassFreqHz: Int = 80         // high-pass cutoff in Hz; 0 = off

    // Conversation mode: when on, the Mac diarizes a recording it transcribes itself (an
    // import, or a phone upload that wasn't already split), re-emitting multi-speaker
    // transcripts as `**[[Person]]:**` / `**Speaker N:**` turns (matched against synced
    // voiceprints). A single-speaker recording is left as plain prose. Mirrors the phone's
    // conversation toggle. Optional so an existing settings.json (written before this
    // field) still decodes (synthesized Decodable throws on a missing NON-optional key) —
    // a nil legacy value reads as ON via `conversationModeEnabled`.
    var conversationMode: Bool? = true
    /// Effective flag (nil legacy → on).
    var conversationModeEnabled: Bool { conversationMode ?? true }

    // Custom-vocabulary boost (CTC spot + rescore after ASR — `VocabularyBooster`):
    // words Parakeet routinely mis-hears, spelled as they should be written.
    // Optional for the same legacy-decode reason as conversationMode.
    var customVocabulary: [String]? = []
    /// Effective list (nil legacy → empty).
    var customWords: [String] { customVocabulary ?? [] }

    static let `default` = AppSettings()

    /// LLM prompts — copied verbatim from `DEFAULT_SETTINGS.enhancement.prompts`.
    /// All steps run on the RAW transcript. (No LLM significance/tagging — those
    /// are manual/deterministic at review.)
    struct Prompts: Codable, Equatable, Sendable {
        var copyEdit: String = Prompts.defaultCopyEdit
        var summary: String = Prompts.defaultSummary
        var title: String = Prompts.defaultTitle

        static let defaultCopyEdit = """
        Clean up this transcript. The author may switch between English and Dutch mid-sentence — this is intentional, keep it exactly as-is.

        Do:
        - Remove filler words (um, uh, like, you know, so basically, I mean, yeah so).
        - Fix spelling and grammar.
        - Add punctuation and paragraph breaks at natural pauses.
        - When the speaker immediately rephrases the same thought (e.g. saying a sentence then saying it again slightly differently), collapse into the final version.
        - Remove false starts and repeated words from thinking out loud.

        Do not:
        - Rephrase, rewrite, or restructure sentences.
        - Translate anything between languages.
        - Add formality — it should still sound like the person speaking.
        - Add any preamble, heading, or explanation.

        Output only the cleaned text.
        """

        static let defaultSummary = """
        Summarize this in 1–3 sentences (30–60 words) as personal notes — the kind of thing you'd jot in a journal, not a report.

        - Use implied first person via present participles: "reflecting on…", "trying to figure out…", "collaborating with…". Avoid "The speaker", "They", "He/She".
        - Drop articles where natural ("importance of X" not "the importance of X").
        - Capture the main point and any decision or action item. If multiple topics, mention each briefly.
        - Use proper spelling and capitalization. Keep names capitalized.
        - IMPORTANT: Write the summary in the SAME language as the input text — if the text is in English, the summary MUST be in English.

        Output only the summary.
        """

        static let defaultTitle = """
        Generate a short, descriptive title for this text (5–15 words). If the speaker explicitly names the topic, use their words. Match the primary language of the text. Return ONLY the title, nothing else.
        """
    }
}

/// Codable load/save for `AppSettings` at `AppPaths.settingsFile`.
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
            return Self.freshDefault
        }
        return parsed
    }

    /// Defaults for a fresh install (no settings file yet). The Debug ("Skrift Dev")
    /// build defaults its export vault to the TEST vault so dev runs NEVER write the
    /// user's real Obsidian vault (privacy). Release ("Skrift") stays empty → the
    /// SetupWizard prompts for the real vault.
    static var freshDefault: AppSettings {
        var s = AppSettings.default
        #if DEBUG
        s.noteFolder = (("~/Hackerman/Obsidian_LLM_Test_Vault") as NSString).expandingTildeInPath
        #endif
        return s
    }

    @discardableResult
    func save(_ settings: AppSettings) -> AppSettings {
        if let encoded = try? encoder.encode(settings) {
            try? encoded.write(to: fileURL)
        }
        return settings
    }
}
