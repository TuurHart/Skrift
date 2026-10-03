import Foundation

/// The iPad's local store for the polish prompts (mirrors `CustomVocabularyStore`'s
/// role for vocab): UserDefaults-backed, synchronous reads for the engine, an LWW
/// stamp for `PolishPromptsCloudSync`. An unset key = the shared default
/// (`PolishPrompts`), so a fresh install polishes with the Mac's exact voice.
enum PolishPromptsStore {
    private static let stampKey = "polishPromptsModifiedAt"

    /// The ONE per-kind descriptor: where it is stored and what an unset/blank/identical
    /// value means (the shared default, `PolishPromptKind.defaultText`).
    private static func descriptor(_ kind: PolishPromptKind) -> (key: String, fallback: String) {
        switch kind {
        case .copyEdit: return ("polishPromptCopyEdit", kind.defaultText)
        case .summary: return ("polishPromptSummary", kind.defaultText)
        case .title: return ("polishPromptTitle", kind.defaultText)
        }
    }

    // MARK: - Effective prompts (what the engine runs)

    /// What the engine runs for `kind`: the stored edit, or the shared default.
    static func text(for kind: PolishPromptKind, defaults: UserDefaults = .standard) -> String {
        let d = descriptor(kind)
        return PolishPrompts.effective(defaults.string(forKey: d.key) ?? "", fallback: d.fallback)
    }

    static func copyEdit(defaults: UserDefaults = .standard) -> String { text(for: .copyEdit, defaults: defaults) }
    static func summary(defaults: UserDefaults = .standard) -> String { text(for: .summary, defaults: defaults) }
    static func title(defaults: UserDefaults = .standard) -> String { text(for: .title, defaults: defaults) }

    static func blob(defaults: UserDefaults = .standard) -> PolishPromptsSyncCore.Blob {
        var blob = PolishPromptsSyncCore.Blob.defaults
        for kind in PolishPromptKind.allCases { blob[kind] = text(for: kind, defaults: defaults) }
        return blob
    }

    /// `.distantPast` = never edited on this device (the core's fresh-device guard).
    static func modifiedAt(defaults: UserDefaults = .standard) -> Date {
        defaults.object(forKey: stampKey) as? Date ?? .distantPast
    }

    /// True when this prompt differs from the shared default (drives the
    /// "edited" vs "default" subtitle in Settings).
    static func isEdited(_ prompt: PolishPromptKind, defaults: UserDefaults = .standard) -> Bool {
        text(for: prompt, defaults: defaults) != prompt.defaultText
    }

    // MARK: - Local edits (Settings editors; stamp = a real user edit)

    static func setText(_ text: String, for prompt: PolishPromptKind,
                        defaults: UserDefaults = .standard) {
        store(text, for: prompt, defaults: defaults)
        defaults.set(Date(), forKey: stampKey)
    }

    /// Adopt a synced blob without minting a new edit stamp (LWW discipline —
    /// mirrors `CustomVocabularyStore.adoptSynced`).
    static func adoptSynced(_ blob: PolishPromptsSyncCore.Blob, modifiedAt: Date,
                            defaults: UserDefaults = .standard) {
        for kind in PolishPromptKind.allCases { store(blob[kind], for: kind, defaults: defaults) }
        defaults.set(modifiedAt, forKey: stampKey)
    }

    // MARK: - plumbing

    /// Empty or byte-identical to the default → store nothing (the default rules).
    private static func store(_ text: String, for kind: PolishPromptKind, defaults: UserDefaults) {
        let d = descriptor(kind)
        if let stored = PolishPrompts.storable(text, fallback: d.fallback) {
            defaults.set(stored, forKey: d.key)
        } else {
            defaults.removeObject(forKey: d.key)
        }
    }
}

// PolishPromptKind (the order + labels) lives in Shared/Pipeline/PolishPrompts.swift (Q187).
