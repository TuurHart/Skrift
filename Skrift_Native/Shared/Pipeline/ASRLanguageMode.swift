import Foundation

/// How the transcriber should treat language — the ONE definition for every device.
///
/// **Why this is shared, and why it matters.** This is not a cosmetic preference: it
/// sets FluidAudio's `melChunkContext`, and the difference was MEASURED on real audio
/// via the desktop `-asrsweep` harness. On a 3-minute Dutch clip the English default
/// (`mel = on`) drifts to the model's English prior and garbles non-English — wrong
/// years (1666 for 1986), invented words ("twaalftig"), mangled place names — which
/// `mel = off` fixes. It's language-agnostic, so it helps any non-English language v3
/// supports. The cost is a small English chunk-seam duplication, so English mode keeps
/// the v3 default.
///
/// Before this type existed the phone/iPad had the setting and **the Mac didn't** — it
/// built `AsrManager(config: .default)`, i.e. permanently English-tuned, so the same
/// audio transcribed down a different path depending on which device did it (and the
/// Mac is what transcribes local imports and ⋯ Re-transcribe). Found 2026-07-26 while
/// hoisting `ASRPostProcess`; Tuur: "make it sync and add the setting to mac."
enum ASRLanguageMode: String, CaseIterable, Sendable, Identifiable {
    /// The v3 default — cleanest English seams.
    case english
    /// `melChunkContext` off — stops the decoder drifting to its English prior.
    case multilingual

    public var id: String { rawValue }

    /// The stored form is a Bool, on both apps, under ONE key name — `false` = English,
    /// matching what the phone shipped so no migration is needed anywhere.
    static let settingKey = "transcriptionMultilingual"

    static func from(multilingual: Bool) -> ASRLanguageMode { multilingual ? .multilingual : .english }

    var isMultilingual: Bool { self == .multilingual }

    /// What to pass FluidAudio as `ASRConfig(melChunkContext:)`. THE reason this type
    /// exists — derive it here, never inline, or the apps drift again.
    var melChunkContext: Bool { !isMultilingual }

    // ── copy (shared so both Settings screens say the same thing) ──

    var label: String {
        switch self {
        case .english:      return "English"
        case .multilingual: return "Multilingual"
        }
    }

    /// The one-line explanation under the control.
    static let footer = "English is cleanest for English-only speech. Multilingual stops the model drifting to English on other languages — pick it if you mix languages. This setting syncs to your other devices."

    // ── per note (C151, D46) ──

    /// The mode a note's transcript was made with: its stored stamp, else the global setting
    /// (a transcript from before the stamp existed was made with whatever the device had then;
    /// the setting is the best guess, and the verb below still offers the other one).
    static func recorded(_ stamp: String?, default fallback: ASRLanguageMode) -> ASRLanguageMode {
        stamp.flatMap(ASRLanguageMode.init(rawValue:)) ?? fallback
    }

    /// The mode "Transcribe again" switches to.
    var other: ASRLanguageMode { isMultilingual ? .english : .multilingual }

    /// The language a person names for this mode in the per-note verb. Multilingual is what a
    /// Dutch note needs (D46: a recognition mode, Parakeet never translates), so it reads Dutch.
    var spokenLanguage: String { isMultilingual ? "Dutch" : "English" }

    /// ⋯ › "Transcribe again in Dutch" on a note made in English mode, "… in English" on one
    /// made in Multilingual. One wording for both apps.
    static func transcribeAgainLabel(recordedIn mode: ASRLanguageMode) -> String {
        "Transcribe again in \(mode.other.spokenLanguage)"
    }

    /// Said when the new pass fails or hears nothing; the note is left as it was.
    static let transcribeAgainFailed = "Couldn't transcribe again. The note is unchanged."
}

/// The phone/iPad's local store for the language mode — a Bool plus its own LWW stamp,
/// in UserDefaults, because `TranscriptionService` reads it synchronously off the main
/// actor (the same reason `CustomVocabularyStore` isn't a `@Model`). The Mac's copy lives
/// in `AppSettings`; both reconcile through `LanguageSyncCore`.
enum ASRLanguageStore {
    static var stampKey: String { ASRLanguageMode.settingKey + "ModifiedAt" }

    static func isMultilingual(defaults: UserDefaults = .standard) -> Bool {
        defaults.bool(forKey: ASRLanguageMode.settingKey)
    }

    /// `.distantPast` until the user actually picks — so a device that never chose can't
    /// push its default over another device's real choice.
    static func modifiedAt(defaults: UserDefaults = .standard) -> Date {
        (defaults.object(forKey: stampKey) as? Date) ?? .distantPast
    }

    /// The user picked a mode here → bump the stamp so it wins LWW.
    static func save(_ mode: ASRLanguageMode, defaults: UserDefaults = .standard) {
        defaults.set(mode.isMultilingual, forKey: ASRLanguageMode.settingKey)
        defaults.set(Date(), forKey: stampKey)
    }

    /// Adopt a value that arrived from another device — keeps the REMOTE stamp, so the
    /// timestamps stay comparable (never bumped to now).
    static func adoptSynced(_ multilingual: Bool, modifiedAt: Date, defaults: UserDefaults = .standard) {
        defaults.set(multilingual, forKey: ASRLanguageMode.settingKey)
        defaults.set(modifiedAt, forKey: stampKey)
    }
}
