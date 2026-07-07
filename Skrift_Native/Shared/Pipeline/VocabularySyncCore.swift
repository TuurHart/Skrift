import Foundation
import SwiftData

/// The custom-vocabulary reconcile — ONE algorithm for every device (phone, iPad, Mac).
/// Whole-list last-write-wins by `modifiedAt`: adding OR removing a word on one device
/// propagates to the others (a union would resurrect deletions). Operates on the shared
/// `VocabularyRecord` carrier; the caller owns fetching/saving and its local store
/// (`CustomVocabularyStore`/UserDefaults on the phone, `AppSettings` on the Mac) and
/// applies the returned outcome.
enum VocabularySyncCore {
    enum Outcome: Equatable {
        /// The carrier is newer — the caller replaces its local list + stamp (and
        /// re-warms its booster).
        case adoptRemote(words: [String], modifiedAt: Date)
        /// Local was newer (or first) — the carrier now holds the local list. When
        /// `seededLocalStamp`, the local store had no stamp yet and should adopt `stamp`.
        case pushedLocal(stamp: Date, seededLocalStamp: Bool)
        /// Nothing to do (timestamps equal, or nothing anywhere yet).
        case noop
    }

    static func reconcile(localWords: [String], localModifiedAt: Date,
                          records: [VocabularyRecord], now: Date = Date(),
                          insert: (VocabularyRecord) -> Void,
                          delete: (VocabularyRecord) -> Void) -> Outcome {
        guard let newest = records.max(by: { $0.modifiedAt < $1.modifiedAt }) else {
            // No carrier yet. Push the local list up so existing vocab isn't lost —
            // BUT a fresh device that has NEVER edited its list (empty + distantPast)
            // must NOT create an empty carrier stamped "now": with whole-list LWW that
            // empty-@-now would clobber another device's real words once it syncs. Wait
            // to RECEIVE instead. (A genuine "I deleted all my words" has a real local
            // stamp, so it still propagates the deletion.)
            guard !localWords.isEmpty || localModifiedAt != .distantPast else { return .noop }
            let seeded = localModifiedAt == .distantPast
            let ts = seeded ? now : localModifiedAt
            insert(VocabularyRecord(words: localWords, modifiedAt: ts))
            return .pushedLocal(stamp: ts, seededLocalStamp: seeded)
        }

        // Collapse any duplicate carriers (two devices each created one pre-sync).
        for extra in records where extra !== newest { delete(extra) }

        if newest.modifiedAt > localModifiedAt {
            return .adoptRemote(words: newest.words, modifiedAt: newest.modifiedAt)
        } else if localModifiedAt > newest.modifiedAt {
            newest.words = localWords
            newest.modifiedAt = localModifiedAt
            return .pushedLocal(stamp: localModifiedAt, seededLocalStamp: false)
        }
        return .noop
    }
}
