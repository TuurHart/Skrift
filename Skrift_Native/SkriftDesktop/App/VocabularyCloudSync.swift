import Foundation
import SwiftData

/// Mac adapter for the shared `VocabularySyncCore` reconcile: the local store is
/// `AppSettings.customVocabulary` (+ `customVocabularyModifiedAt`, the Mac's LWW stamp).
/// FULL participant since 2026-07-07 — a word added on the Mac reaches the phone, and a
/// deletion on either side propagates (the Mac used to be consume-only union: Mac-added
/// words never synced, deletions never landed). Runs from `MemoCloudReconciler` on
/// launch / foreground / import, and from Settings on a vocab edit (push-on-edit).
/// No-op unless CloudKit-Mac sync is on.
@MainActor
enum VocabularyCloudSync {
    static func run() {
        var settings = SettingsStore.shared.load()
        guard settings.cloudKitMacSyncEnabled, let container = MemoCloudStore.container else { return }
        let context = container.mainContext
        let records = (try? context.fetch(FetchDescriptor<VocabularyRecord>())) ?? []

        // One-time migration from the consume-only era: the Mac has words but no stamp
        // (it never dated its edits). UNION them into the newest carrier's list — keeping
        // the old guarantee that no Mac-local word is lost — and stamp the union as a
        // fresh edit; whole-list LWW takes over from here.
        if settings.customVocabularyModifiedAt == nil, !settings.customWords.isEmpty,
           let newest = records.max(by: { $0.modifiedAt < $1.modifiedAt }) {
            var seen = Set(newest.words.map { $0.lowercased() })
            var union = newest.words
            for w in settings.customWords where seen.insert(w.lowercased()).inserted { union.append(w) }
            settings.customVocabulary = union
            settings.customVocabularyModifiedAt = Date()
            SettingsStore.shared.save(settings)
            let words = union
            Task.detached(priority: .utility) { await VocabularyBooster.shared.prewarm(words: words) }
        }

        let localWords = settings.customWords
        let outcome = VocabularySyncCore.reconcile(
            localWords: localWords,
            localModifiedAt: settings.customVocabularyModifiedAt ?? .distantPast,
            records: records,
            insert: { context.insert($0) },
            delete: { context.delete($0) })

        switch outcome {
        case .adoptRemote(let words, let ts):
            settings.customVocabulary = words
            settings.customVocabularyModifiedAt = ts
            SettingsStore.shared.save(settings)
            // Re-warm the booster so the newly-synced words boost the NEXT transcription.
            Task.detached(priority: .utility) { await VocabularyBooster.shared.prewarm(words: words) }
        case .pushedLocal(let ts, seededLocalStamp: true):
            settings.customVocabularyModifiedAt = ts
            SettingsStore.shared.save(settings)
        case .pushedLocal, .noop:
            break
        }
        try? context.save()
    }
}
