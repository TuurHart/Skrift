import Foundation
import SwiftData

/// Phone adapter for the shared `VocabularySyncCore` reconcile (Phase 1f): the local
/// store is `CustomVocabularyStore` (UserDefaults — the booster reads it synchronously).
/// Runs on launch + foreground alongside the other sync sweeps, and on a Settings edit
/// (push-on-edit). The algorithm itself is the shared core — identical on the Mac.
@MainActor
enum VocabularyCloudSync {

    static func run(_ repository: NotesRepository, defaults: UserDefaults = .standard) {
        let localWords = CustomVocabularyStore.words(defaults: defaults)
        let records = repository.allVocabularyRecords()
        let outcome = VocabularySyncCore.reconcile(
            localWords: localWords,
            localModifiedAt: CustomVocabularyStore.modifiedAt(defaults: defaults),
            records: records,
            insert: { repository.context.insert($0) },
            delete: { repository.context.delete($0) })

        switch outcome {
        case .adoptRemote(let words, let ts):
            CustomVocabularyStore.adoptSynced(words, modifiedAt: ts, defaults: defaults)
            DevLog.log("vocab: adopted \(words.count) synced words")
        case .pushedLocal(let ts, seededLocalStamp: true):
            CustomVocabularyStore.adoptSynced(localWords, modifiedAt: ts, defaults: defaults)
        case .pushedLocal, .noop:
            break
        }
        // Fresh device with nothing anywhere: no carrier was touched, nothing to save.
        if records.isEmpty, outcome == .noop { return }
        repository.save()
    }
}
