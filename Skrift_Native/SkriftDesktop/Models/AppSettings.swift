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
    var enhancementModelRepo: String = PolishPrompts.defaultModelRepo
    var prompts: Prompts = .init()

    // Transcription preprocessing (native AVFoundation): high-pass + peak normalize →
    // 16 kHz mono before ASR. (afftdn-style noise reduction has no faithful native
    // equivalent, so it's intentionally not offered — see A4.)
    var highpassFreqHz: Int = 80         // high-pass cutoff in Hz; 0 = off

    // Conversation mode: when on, the Mac diarizes a recording it transcribes itself (an
    // import, or a phone upload that wasn't already split), re-emitting multi-speaker
    // transcripts as `**[[Person]]:**` / `**Speaker N:**` turns (matched against synced
    // voiceprints). A single-speaker recording is left as plain prose. Optional so an
    // existing settings.json (written before this field) still decodes.
    // ⚠️ DEFAULT OFF (user call 2026-06-15): an always-on global auto-diarize ran Sortformer
    // over EVERY Mac transcription and over-split monologues into "Speaker 1/2". Diarization
    // is now a deliberate PER-NOTE action ("Split speakers" in the review menu); this global
    // flag only matters for the unattended batch run, and stays off unless explicitly enabled.
    var conversationMode: Bool? = nil
    /// Effective flag (nil → OFF; auto-diarize on batch-process only when explicitly on).
    var conversationModeEnabled: Bool { conversationMode ?? false }

    /// Skip the Gemma summary for notes shorter than this many words (user 2026-06-15 —
    /// short memos don't need one). Optional for legacy decode; nil → 75.
    var summaryMinWords: Int? = nil
    var effectiveSummaryMinWords: Int { summaryMinWords ?? 75 }

    // Custom-vocabulary boost (CTC spot + rescore after ASR — `VocabularyBooster`):
    // words Parakeet routinely mis-hears, spelled as they should be written.
    // Optional for the same legacy-decode reason as conversationMode.
    var customVocabulary: [String]? = []
    /// Effective list (nil legacy → empty).
    var customWords: [String] { customVocabulary ?? [] }

    /// When the Mac last EDITED its custom-vocabulary list (Settings add/remove) — the
    /// Mac's side of the whole-list-LWW vocab sync (`VocabularySyncCore`). nil = never
    /// edited / pre-LWW legacy (treated as distantPast; optional for legacy decode).
    /// The DEBUG `-runfile -vocab` harness deliberately does NOT stamp this, so
    /// harness-injected words can never win LWW over a real device's list.
    var customVocabularyModifiedAt: Date? = nil

    /// When the Mac last EDITED a polish prompt (Settings TextEditor) — the Mac's
    /// side of the whole-blob-LWW prompt sync with the iPad's polisher
    /// (`PolishPromptsSyncCore`). nil = never edited (treated as distantPast;
    /// optional for legacy decode).
    var promptsModifiedAt: Date? = nil

    // ── CloudKit-Mac sync (MAC_CLOUDKIT_PLAN.md 8d) ──
    // When on, the Mac reconciles memos synced over CloudKit (from the phone's note store)
    // into the local pipeline queue (`MemoCloudReconciler`) and writes its polish back as a
    // `MemoEnhancement` (8c). OFF by default (opt-in): CloudKit needs the iCloud capability +
    // the user signed into iCloud on the Mac, and the Bonjour/HTTP path stays the default
    // until the user turns this on. Optional for legacy-decode (same pattern as conversationMode).
    var cloudKitMacSync: Bool? = nil
    /// Effective flag (nil → OFF). When false, `MemoCloudReconciler` is inert and only the
    /// Bonjour/HTTP path ingests — the two transports coexist.
    var cloudKitMacSyncEnabled: Bool { cloudKitMacSync ?? false }

    /// When on, the Mac processes EVERY synced memo, ignoring the phone's significance>0
    /// flag-to-send gate (the `MemoCloudIngest` `processEverything` override). OFF by default
    /// → honor the phone's intent (significance 0 is synced but skipped). Optional for legacy-decode.
    /// DEAD since 2026-07-21 — the Queue band's "Process all N" replaced it as the one
    /// visible control (Q6, mocks/lifecycle-ia-explorations.html); field kept for legacy decode.
    var processAllSyncedMemos: Bool? = nil

    static let `default` = AppSettings()

    /// LLM prompts — copied verbatim from `DEFAULT_SETTINGS.enhancement.prompts`.
    /// All steps run on the RAW transcript. (No LLM significance/tagging — those
    /// are manual/deterministic at review.)
    struct Prompts: Codable, Equatable, Sendable {
        var copyEdit: String = Prompts.defaultCopyEdit
        var summary: String = Prompts.defaultSummary
        var title: String = Prompts.defaultTitle

        // Single-sourced with the iPad's on-demand polisher (wave 1, 2026-07-22):
        // the default prompt TEXT lives in Shared/Pipeline/PolishPrompts.swift so
        // the two polishers can never drift. A user-tuned override in settings.json
        // still wins here (these are only the defaults).
        static let defaultCopyEdit = PolishPrompts.copyEdit
        static let defaultSummary = PolishPrompts.summary
        static let defaultTitle = PolishPrompts.title
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
