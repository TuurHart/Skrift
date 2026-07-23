import Foundation

/// The iPad's local store for the polish prompts (mirrors `CustomVocabularyStore`'s
/// role for vocab): UserDefaults-backed, synchronous reads for the engine, an LWW
/// stamp for `PolishPromptsCloudSync`. An unset key = the shared default
/// (`PolishPrompts`), so a fresh install polishes with the Mac's exact voice.
enum PolishPromptsStore {
    private static let copyEditKey = "polishPromptCopyEdit"
    private static let summaryKey = "polishPromptSummary"
    private static let titleKey = "polishPromptTitle"
    private static let stampKey = "polishPromptsModifiedAt"

    // MARK: - Effective prompts (what the engine runs)

    static func copyEdit(defaults: UserDefaults = .standard) -> String {
        text(copyEditKey, fallback: PolishPrompts.copyEdit, defaults: defaults)
    }
    static func summary(defaults: UserDefaults = .standard) -> String {
        text(summaryKey, fallback: PolishPrompts.summary, defaults: defaults)
    }
    static func title(defaults: UserDefaults = .standard) -> String {
        text(titleKey, fallback: PolishPrompts.title, defaults: defaults)
    }

    static func blob(defaults: UserDefaults = .standard) -> PolishPromptsSyncCore.Blob {
        .init(copyEdit: copyEdit(defaults: defaults),
              summary: summary(defaults: defaults),
              title: title(defaults: defaults))
    }

    /// `.distantPast` = never edited on this device (the core's fresh-device guard).
    static func modifiedAt(defaults: UserDefaults = .standard) -> Date {
        defaults.object(forKey: stampKey) as? Date ?? .distantPast
    }

    /// True when this prompt differs from the shared default (drives the
    /// "edited" vs "default" subtitle in Settings).
    static func isEdited(_ prompt: PolishPromptKind, defaults: UserDefaults = .standard) -> Bool {
        switch prompt {
        case .copyEdit: return copyEdit(defaults: defaults) != PolishPrompts.copyEdit
        case .summary: return summary(defaults: defaults) != PolishPrompts.summary
        case .title: return title(defaults: defaults) != PolishPrompts.title
        }
    }

    // MARK: - Local edits (Settings editors; stamp = a real user edit)

    static func setText(_ text: String, for prompt: PolishPromptKind,
                        defaults: UserDefaults = .standard) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let key = key(for: prompt)
        let fallback = fallbackText(for: prompt)
        // Empty or byte-identical to the default → store nothing (the default rules).
        if trimmed.isEmpty || trimmed == fallback {
            defaults.removeObject(forKey: key)
        } else {
            defaults.set(trimmed, forKey: key)
        }
        defaults.set(Date(), forKey: stampKey)
    }

    /// Adopt a synced blob without minting a new edit stamp (LWW discipline —
    /// mirrors `CustomVocabularyStore.adoptSynced`).
    static func adoptSynced(_ blob: PolishPromptsSyncCore.Blob, modifiedAt: Date,
                            defaults: UserDefaults = .standard) {
        store(blob.copyEdit, at: copyEditKey, fallback: PolishPrompts.copyEdit, defaults: defaults)
        store(blob.summary, at: summaryKey, fallback: PolishPrompts.summary, defaults: defaults)
        store(blob.title, at: titleKey, fallback: PolishPrompts.title, defaults: defaults)
        defaults.set(modifiedAt, forKey: stampKey)
    }

    // MARK: - plumbing

    private static func text(_ key: String, fallback: String, defaults: UserDefaults) -> String {
        let stored = defaults.string(forKey: key)
        return (stored?.isEmpty == false ? stored : nil) ?? fallback
    }

    private static func store(_ text: String, at key: String, fallback: String,
                              defaults: UserDefaults) {
        if text == fallback || text.isEmpty {
            defaults.removeObject(forKey: key)
        } else {
            defaults.set(text, forKey: key)
        }
    }

    private static func key(for prompt: PolishPromptKind) -> String {
        switch prompt {
        case .copyEdit: return copyEditKey
        case .summary: return summaryKey
        case .title: return titleKey
        }
    }

    private static func fallbackText(for prompt: PolishPromptKind) -> String {
        switch prompt {
        case .copyEdit: return PolishPrompts.copyEdit
        case .summary: return PolishPrompts.summary
        case .title: return PolishPrompts.title
        }
    }
}

enum PolishPromptKind: CaseIterable {
    case copyEdit, summary, title

    var label: String {
        switch self {
        case .copyEdit: return "Copy-edit prompt"
        case .summary: return "Summary prompt"
        case .title: return "Title prompt"
        }
    }
}
