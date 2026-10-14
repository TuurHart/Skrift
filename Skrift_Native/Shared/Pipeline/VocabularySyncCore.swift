import Foundation
import SwiftData

/// The custom-vocabulary reconcile — ONE algorithm for every device (phone, iPad, Mac).
/// Both adapters call `sync`: when the device and the carrier both hold a `VocabularyLedger`
/// it MERGES per word (C267 / R80), so a word added offline on two devices survives on both
/// and a removal on either still removes. When either side predates the ledger, `sync`
/// falls back to `reconcile`, whole-list last-write-wins by `modifiedAt` (a plain union would
/// resurrect deletions), and seeds the ledger on both sides. Operates on the shared
/// `VocabularyRecord` carrier; the caller owns fetching/saving and its local store
/// (`CustomVocabularyStore`/UserDefaults on the phone, `AppSettings` on the Mac) and
/// applies the returned state.
enum VocabularySyncCore {
    /// One device's own copy of the list.
    struct LocalVocab: Equatable {
        var words: [String]
        /// `.distantPast` = never edited on this device.
        var modifiedAt: Date
        /// nil = written before the ledger existed.
        var ledger: VocabularyLedger?
    }

    struct SyncResult: Equatable {
        /// What the device stores now.
        var local: LocalVocab
        /// The device must write `local` back to its store.
        var localChanged: Bool
        /// The word list itself changed: re-warm the booster.
        var wordsChanged: Bool
    }

    /// Reconciles this device's list with the carrier rows. See the type comment.
    static func sync(local: LocalVocab, records: [VocabularyRecord], now: Date = Date(),
                     insert: (VocabularyRecord) -> Void,
                     delete: (VocabularyRecord) -> Void) -> SyncResult {
        if let localLedger = local.ledger,
           let newest = records.max(by: { $0.modifiedAt < $1.modifiedAt }),
           let carrierLedger = VocabularyLedger.decode(newest.wordLedger) {
            // Merge EVERY ledgered carrier (two devices may each have created one offline),
            // then collapse to the newest row.
            var merged = localLedger
            var stamp = max(local.modifiedAt, newest.modifiedAt)
            for record in records {
                guard let ledger = VocabularyLedger.decode(record.wordLedger) else { continue }
                merged = merged.merged(with: ledger)
                stamp = max(stamp, record.modifiedAt)
            }
            for extra in records where extra !== newest { delete(extra) }
            if merged != carrierLedger {
                newest.wordLedger = merged.encoded()
                newest.words = merged.words(keepingOrderOf: newest.words)
                newest.modifiedAt = stamp
            }
            let words = merged.words(keepingOrderOf: local.words)
            let next = LocalVocab(words: words, modifiedAt: stamp, ledger: merged)
            return SyncResult(local: next, localChanged: next != local,
                              wordsChanged: words != local.words)
        }

        // Legacy fallback: whole-list LWW, then seed the ledger on both sides.
        var inserted: VocabularyRecord?
        let outcome = reconcile(localWords: local.words, localModifiedAt: local.modifiedAt,
                                records: records, now: now,
                                insert: { inserted = $0; insert($0) }, delete: delete)
        let carrier = inserted ?? records.max(by: { $0.modifiedAt < $1.modifiedAt })
        switch outcome {
        case .adoptRemote(let words, let ts):
            // A ledgered carrier hands over its own ledger (its removals included).
            let ledger = VocabularyLedger.decode(carrier?.wordLedger)
                ?? VocabularyLedger.seeded(from: words, at: ts)
            carrier?.wordLedger = ledger.encoded()
            return SyncResult(local: LocalVocab(words: words, modifiedAt: ts, ledger: ledger),
                              localChanged: true, wordsChanged: words != local.words)
        case .pushedLocal(let ts, _):
            let ledger = local.ledger ?? VocabularyLedger.seeded(from: local.words, at: ts)
            carrier?.wordLedger = ledger.encoded()
            let next = LocalVocab(words: local.words, modifiedAt: ts, ledger: ledger)
            return SyncResult(local: next, localChanged: next != local, wordsChanged: false)
        case .noop:
            guard let carrier else {
                return SyncResult(local: local, localChanged: false, wordsChanged: false)
            }
            // Equal stamps: same list. Give whichever side lacks a ledger the other's.
            let ledger = local.ledger
                ?? VocabularyLedger.decode(carrier.wordLedger)
                ?? VocabularyLedger.seeded(from: local.words, at: local.modifiedAt)
            if VocabularyLedger.decode(carrier.wordLedger) == nil { carrier.wordLedger = ledger.encoded() }
            let next = LocalVocab(words: local.words, modifiedAt: local.modifiedAt, ledger: ledger)
            return SyncResult(local: next, localChanged: next != local, wordsChanged: false)
        }
    }

    /// A user edit on one device.
    enum Edit: Equatable {
        case add(String)
        case remove(String)
    }

    /// Applies `edit` to the device's CURRENT stored list (the caller re-reads its store
    /// right before calling, never a copy loaded when the screen opened) and records it in
    /// the ledger stamped `now`. nil = nothing changed (empty or duplicate add, unknown word).
    static func applying(_ edit: Edit, to local: LocalVocab, now: Date = Date()) -> LocalVocab? {
        var ledger = local.ledger ?? VocabularyLedger.seeded(from: local.words, at: local.modifiedAt)
        let words: [String]
        switch edit {
        case .add(let typed):
            guard let updated = adding(typed, to: local.words), let word = updated.last else { return nil }
            ledger.add(word, at: now)
            words = updated
        case .remove(let word):
            let key = word.lowercased()
            let updated = local.words.filter { $0.lowercased() != key }
            guard updated.count != local.words.count else { return nil }
            ledger.remove(word, at: now)
            words = updated
        }
        return LocalVocab(words: words, modifiedAt: max(now, local.modifiedAt), ledger: ledger)
    }

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

    /// Whole-list LWW — the pre-ledger rule, used by `sync` when either side has no ledger.
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

    /// The add-custom-word rule (Q172, setexp-31) both Settings screens ran by hand: trim,
    /// refuse empty, refuse a case-insensitive duplicate, append. Returns the new list, or
    /// nil when nothing is added (the caller still clears its field). The caller stamps,
    /// persists and pushes.
    static func adding(_ typed: String, to words: [String]) -> [String]? {
        let trimmed = typed.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              !words.contains(where: { $0.lowercased() == trimmed.lowercased() })
        else { return nil }
        return words + [trimmed]
    }
}
