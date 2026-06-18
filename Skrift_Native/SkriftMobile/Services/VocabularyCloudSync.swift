import Foundation
import SwiftData

/// Reconciles the local custom-vocabulary list (`CustomVocabularyStore`, UserDefaults)
/// with the CloudKit-synced `VocabularyRecord` carrier (Phase 1f). Runs on launch +
/// foreground alongside the other sync sweeps.
///
/// Last-write-wins by `modifiedAt` (whole list) — so adding OR removing a word on one
/// device propagates to the others. A union would never let a deletion stick (the
/// other device's copy would resurrect it). Concurrent edits on two devices before
/// they sync resolve to the newer one (acceptable for a small per-user word list).
@MainActor
enum VocabularyCloudSync {

    static func run(_ repository: NotesRepository, defaults: UserDefaults = .standard) {
        let localWords = CustomVocabularyStore.words(defaults: defaults)
        let localTS = CustomVocabularyStore.modifiedAt(defaults: defaults)

        let records = repository.allVocabularyRecords()
        guard let newest = records.max(by: { $0.modifiedAt < $1.modifiedAt }) else {
            // No carrier yet. Push the local list up so existing vocab isn't lost —
            // BUT a fresh device that has NEVER edited its list (empty + distantPast)
            // must NOT create an empty carrier stamped "now": with whole-list LWW that
            // empty-@-now would clobber another device's real words once it syncs. Wait
            // to RECEIVE instead. (A genuine "I deleted all my words" has localTS !=
            // distantPast, so it still propagates the deletion.)
            guard !localWords.isEmpty || localTS != .distantPast else { return }
            let ts = localTS == .distantPast ? Date() : localTS
            repository.context.insert(VocabularyRecord(words: localWords, modifiedAt: ts))
            if localTS == .distantPast { CustomVocabularyStore.adoptSynced(localWords, modifiedAt: ts, defaults: defaults) }
            repository.save()
            return
        }

        // Collapse any duplicate carriers (two devices each created one pre-sync).
        for extra in records where extra !== newest { repository.context.delete(extra) }

        if newest.modifiedAt > localTS {
            CustomVocabularyStore.adoptSynced(newest.words, modifiedAt: newest.modifiedAt, defaults: defaults)
            DevLog.log("vocab: adopted \(newest.words.count) synced words")
        } else if localTS > newest.modifiedAt {
            newest.words = localWords
            newest.modifiedAt = localTS
        }
        repository.save()
    }
}
