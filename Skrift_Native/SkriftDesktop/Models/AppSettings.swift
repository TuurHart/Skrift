import Foundation

/// User-configurable settings, persisted to `AppPaths.settingsFile`. Mirrors the
/// subset of `backend/config/settings.py` the native app needs.
struct AppSettings: Codable, Equatable, Sendable {
    // Export → Obsidian vault. Subfolders are fixed (`VaultLayout`), not settings; an old settings.json that still carries `audioFolder`/`attachmentsFolder` decodes fine (unknown keys are ignored).
    var noteFolder: String = ""          // vault root
    /// The PORTFOLIO root — the folder `_projects` / `_ideas` / `_inspiration` live inside
    /// (`NoteDestination.portfolioFolder`). One pick, not three: they are siblings, so asking
    /// three times would just be three chances to answer the same question wrong. Stored as
    /// a path like `noteFolder`; iOS keeps the same thing as a security-scoped bookmark.
    ///
    /// OPTIONAL, like `customVocabulary` — a synthesized `Codable` does NOT fall back to a
    /// property's default when the key is missing, it THROWS, so a non-optional field here
    /// would fail to decode every settings.json written before today and silently reset the
    /// vault path, the author and the prompts along with it. `CustomVocabularyTests` caught
    /// exactly that.
    var portfolioFolder: String? = nil

    /// Non-optional accessor for the UI and the exporter — empty means "not set".
    var portfolioRoot: String {
        get { portfolioFolder ?? "" }
        set { portfolioFolder = newValue.isEmpty ? nil : newValue }
    }

    var authorName: String = ""
    /// LWW stamp for `authorName` ALONE (`AuthorSyncCore`, Q158) — the author syncs with the
    /// iPad's export author. nil = never edited on this Mac (optional for legacy decode).
    var authorModifiedAt: Date? = nil

    // Enhancement model (shipped default = the tuned 8bit; downloaded from HF on first run)
    var enhancementModelRepo: String = PolishPrompts.defaultModelRepo
    var prompts: Prompts = .init()

    // Transcription preprocessing (native AVFoundation): high-pass + peak normalize →
    // 16 kHz mono before ASR. (afftdn-style noise reduction has no faithful native
    // equivalent, so it's intentionally not offered — see A4.)
    var highpassFreqHz: Int = 80         // high-pass cutoff in Hz; 0 = off

    /// Skip the Gemma summary for notes shorter than this many words (user 2026-06-15 —
    /// short memos don't need one). Optional for legacy decode; nil → 75.
    var summaryMinWords: Int? = nil
    var effectiveSummaryMinWords: Int { summaryMinWords ?? SummaryRule.defaultMinWords }   // shared with the iPad (Q172)

    // Custom-vocabulary boost (CTC spot + rescore after ASR — `VocabularyBooster`):
    // words Parakeet routinely mis-hears, spelled as they should be written.
    // Optional for legacy decode: a synthesized Codable THROWS on a missing key.
    var customVocabulary: [String]? = []
    /// Effective list (nil legacy → empty).
    var customWords: [String] { customVocabulary ?? [] }

    /// When the Mac last EDITED its custom-vocabulary list (Settings add/remove) — the
    /// Mac's side of the whole-list-LWW vocab sync (`VocabularySyncCore`). nil = never
    /// edited / pre-LWW legacy (treated as distantPast; optional for legacy decode).
    /// The DEBUG `-runfile -vocab` harness deliberately does NOT stamp this, so
    /// harness-injected words can never win LWW over a real device's list.
    var customVocabularyModifiedAt: Date? = nil

    /// Transcription language mode — `false` = English (see `ASRLanguageMode`, shared).
    /// The Mac had NO such setting until 2026-07-26: it built `AsrManager(config:
    /// .default)`, i.e. permanently English-tuned, while the phone/iPad could choose —
    /// so the same audio transcribed differently depending on the device, and Dutch was
    /// measurably worse on the Mac. Syncs via `LanguageSyncCore`.
    /// OPTIONAL for legacy decode (a missing key THROWS in a synthesized Codable): a
    /// non-optional Bool makes `AppSettings` fail to decode from any settings file
    /// written before this field existed — i.e. every real install. (An existing test,
    /// `testLegacySettingsDecodeWithoutCustomVocabulary`, caught exactly that.)
    var transcriptionMultilingual: Bool? = nil
    /// Effective value (nil legacy → English, matching the phone's default).
    var transcriptionIsMultilingual: Bool { transcriptionMultilingual ?? false }
    /// LWW stamp for `transcriptionMultilingual` ALONE (independent of the vocab stamp,
    /// so the two settings can't clobber each other). nil = never chosen on this Mac,
    /// which must NOT push its default over another device's real choice.
    var transcriptionLanguageModifiedAt: Date? = nil

    /// When the Mac last EDITED a polish prompt (Settings TextEditor) — the Mac's
    /// side of the whole-blob-LWW prompt sync with the iPad's polisher
    /// (`PolishPromptsSyncCore`). nil = never edited (treated as distantPast;
    /// optional for legacy decode).
    var promptsModifiedAt: Date? = nil

    // ── CloudKit-Mac sync (MAC_CLOUDKIT_PLAN.md 8d) ──
    // When on, the Mac reconciles memos synced over CloudKit (from the phone's note store)
    // into the local pipeline queue (`MemoCloudReconciler`) and writes its polish back as a
    // `MemoEnhancement` (8c). Optional for legacy-decode (same pattern as customVocabulary);
    // an explicit stored `false` still wins, so anyone who deliberately turned it off stays off.
    var cloudKitMacSync: Bool? = nil
    /// Effective flag. **Defaults ON since 2026-07-26.** It shipped opt-out-by-default back
    /// when the Bonjour/HTTP path was the fallback — but Bonjour was retired 2026-07-06 and
    /// CloudKit is now the ONLY phone↔Mac transport. Nine subsystems gate on this flag
    /// (reconcile, names, vocab, edit/delete/meta write-back, lifecycle sweep, processing),
    /// so a nil default meant a fresh Mac install silently synced NOTHING and simply looked
    /// broken. nil → ON; an explicit user `false` is still honoured.
    var cloudKitMacSyncEnabled: Bool { cloudKitMacSync ?? true }

    static let `default` = AppSettings()

    /// LLM prompts — copied verbatim from `DEFAULT_SETTINGS.enhancement.prompts`.
    /// All steps run on the RAW transcript. (No LLM significance/tagging — those
    /// are manual/deterministic at review.)
    struct Prompts: Codable, Equatable, Sendable {
        var copyEdit: String = PolishPrompts.copyEdit
        var summary: String = PolishPrompts.summary
        var title: String = PolishPrompts.title

        // The blank rule (Q157): a blank prompt IS the shared default — what the
        // polisher sends and what syncs. The raw field may sit blank while the user
        // types a replacement; nothing downstream ever sees the blank.
        var effectiveCopyEdit: String { PolishPrompts.effective(copyEdit, fallback: PolishPrompts.copyEdit) }
        var effectiveSummary: String { PolishPrompts.effective(summary, fallback: PolishPrompts.summary) }
        var effectiveTitle: String { PolishPrompts.effective(title, fallback: PolishPrompts.title) }

        /// All three through the blank rule (blank → default text, others trimmed).
        var effective: Prompts {
            Prompts(copyEdit: effectiveCopyEdit, summary: effectiveSummary, title: effectiveTitle)
        }
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

    /// Q18/C265/R78: a present-but-undecodable `settings.json` is never adopted
    /// as "fresh install empty" — `SafeJSONStore` quarantines the bad file
    /// (to `settings.json.corrupt-<timestamp>`, preserved, recovery surfaced)
    /// before this falls back to `freshDefault` for the running session. A
    /// genuinely missing file (real fresh install) also gets `freshDefault`,
    /// same as before.
    func load() -> AppSettings {
        let outcome = SafeJSONStore.load(AppSettings.self, from: fileURL, decoder: decoder)
        // C102: diarization is opt-in PER NOTE (`PipelineFile.diarizeRequested`). An older build
        // persisted a global `conversationMode` = true; the key is gone from this struct, so an
        // old settings.json still decodes (unknown keys are ignored) and can never diarize.
        return outcome.value ?? Self.freshDefault
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
        SafeJSONStore.write(settings, to: fileURL, encoder: encoder)
        return settings
    }

    /// Q241 (6): persist ONLY what the user changed in an open editor. The Settings sheet holds
    /// a copy of settings.json taken when it opened, while the CloudKit runners (vocab, language,
    /// prompts) write newer values to disk behind it; saving the whole stale copy on the next
    /// autosave wrote those older values back. This reloads the file, applies just the keys that
    /// differ between `base` (what the editor last loaded or saved) and `edited`, and writes the
    /// result — every field the editor did not touch keeps whatever is on disk now.
    @discardableResult
    func saveEdit(from base: AppSettings, to edited: AppSettings) -> AppSettings {
        func dict(_ s: AppSettings) -> [String: Any] {
            guard let d = try? encoder.encode(s),
                  let o = try? JSONSerialization.jsonObject(with: d) as? [String: Any] else { return [:] }
            return o
        }
        let b = dict(base), e = dict(edited)
        var merged = dict(load())
        for key in Set(b.keys).union(e.keys) {
            let bv = b[key], ev = e[key]
            let same: Bool
            switch (bv, ev) {
            case (nil, nil): same = true
            case let (x?, y?): same = (x as? NSObject)?.isEqual(y) ?? false
            default: same = false
            }
            if !same { merged[key] = ev }   // nil removes the key (an optional the user cleared)
        }
        guard let data = try? JSONSerialization.data(withJSONObject: merged),
              let result = try? decoder.decode(AppSettings.self, from: data) else {
            return save(edited)   // cannot happen for a valid AppSettings; never lose the edit
        }
        return save(result)
    }
}
