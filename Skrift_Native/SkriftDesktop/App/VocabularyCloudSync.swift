import Foundation
import SwiftData

/// Mac side of the CloudKit **custom-vocabulary** carrier (parity fix): adopt the phone's
/// synced custom words into the Mac's ASR booster, so a word added on the phone also boosts
/// Mac transcription. The phone authors the `VocabularyRecord` (LWW by `modifiedAt`); the Mac
/// is **consume-only** — it unions the newest cloud words into `AppSettings.customVocabulary`
/// without writing the record back (so it never fights the phone's authoritative LWW).
///
/// Additive by design: it never removes a Mac-local word, so a phone-side *deletion* won't
/// propagate to the Mac (acceptable for a booster list — extra boost words are harmless; full
/// bidirectional LWW would need a Mac-side vocab timestamp, a follow-up). Runs from
/// `MemoCloudReconciler` on launch / foreground / import. No-op unless CloudKit-Mac sync is on.
@MainActor
enum VocabularyCloudSync {
    static func run() {
        guard SettingsStore.shared.load().cloudKitMacSyncEnabled,
              let container = MemoCloudStore.container else { return }
        let records = (try? container.mainContext.fetch(FetchDescriptor<VocabularyRecord>())) ?? []
        guard let newest = records.max(by: { $0.modifiedAt < $1.modifiedAt }), !newest.words.isEmpty else { return }

        var settings = SettingsStore.shared.load()
        let current = settings.customWords
        // Union, case-insensitively de-duped, preserving the Mac's existing entries + order.
        var seen = Set(current.map { $0.lowercased() })
        var merged = current
        for w in newest.words {
            let key = w.lowercased()
            if !seen.contains(key) { seen.insert(key); merged.append(w) }
        }
        guard merged != current else { return }

        settings.customVocabulary = merged
        SettingsStore.shared.save(settings)
        // Re-warm the booster so the newly-synced words boost the NEXT transcription.
        Task.detached(priority: .utility) { await VocabularyBooster.shared.prewarm(words: merged) }
    }
}
