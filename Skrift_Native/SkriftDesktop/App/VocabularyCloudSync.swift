import Foundation
import SwiftData
import os

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
        // Fresh context — mainContext reads stale after a CloudKit import (same trap as the memo
        // sweep); a phone vocab edit lands in a VocabularyRecord blob the Mac must read fresh.
        let context = ModelContext(container)
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

        // The LANGUAGE mode rides the same carrier on its OWN stamp (2026-07-26), so a
        // vocab edit here and a language change on the phone can't clobber each other.
        // Adopting a remote value must drop the loaded ASR manager — its config is baked
        // in — so the next transcription rebuilds with the right one.
        switch LanguageSyncCore.reconcile(
            localMultilingual: settings.transcriptionIsMultilingual,
            localModifiedAt: settings.transcriptionLanguageModifiedAt ?? .distantPast,
            records: records) {
        case .adoptRemote(let multilingual, let ts):
            settings.transcriptionMultilingual = multilingual
            settings.transcriptionLanguageModifiedAt = ts
            SettingsStore.shared.save(settings)
            Task { await TranscriptionService.shared.unload() }
        case .pushedLocal, .noop:
            break
        }

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
        // The "Separate destinations" switch rides the same carrier on a THIRD stamp
        // (Q98 / D162). Re-fetch: the vocab reconcile above may just have inserted the row.
        DestinationSettings.seedStampIfNeeded()
        switch DestinationsSyncCore.reconcile(
            localEnabled: DestinationSettings.storedEnabled(),
            localModifiedAt: DestinationSettings.modifiedAt(),
            records: (try? context.fetch(FetchDescriptor<VocabularyRecord>())) ?? [],
            insert: { context.insert($0) }) {
        case .adoptRemote(let enabled, let ts):
            DestinationSettings.adoptSynced(enabled, modifiedAt: ts)
        case .pushedLocal, .noop:
            break
        }
        // The export AUTHOR rides the same carrier on a FOURTH stamp (Q158). A name set before
        // this synced has no stamp: date it now so it reaches the iPad instead of losing to a blank.
        if settings.authorModifiedAt == nil, !settings.authorName.isEmpty {
            settings.authorModifiedAt = Date()
            SettingsStore.shared.save(settings)
        }
        switch AuthorSyncCore.reconcile(
            localName: settings.authorName,
            localModifiedAt: settings.authorModifiedAt ?? .distantPast,
            records: (try? context.fetch(FetchDescriptor<VocabularyRecord>())) ?? [],
            insert: { context.insert($0) }) {
        case .adoptRemote(let name, let ts):
            settings.authorName = name
            settings.authorModifiedAt = ts
            SettingsStore.shared.save(settings)
        case .pushedLocal, .noop:
            break
        }
        do { try context.save() }
        catch {
            Logger(subsystem: "com.skrift.desktop", category: "cloudkit")
                .error("vocab sync save FAILED — carrier not persisted: \(error)")
        }
    }
}
