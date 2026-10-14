import Foundation

/// Per-word add/remove stamps for the custom-vocabulary list (C267 / R80), so two devices
/// that each edit the list offline MERGE instead of one whole list overwriting the other.
///
/// A word is present when it was added after its last removal. Two ledgers merge entry by
/// entry (latest add, latest removal), so a word added offline on the phone and another
/// added offline on the Mac both survive, while a removal on either device still removes
/// (its removal stamp beats the older add). Keyed case-insensitively, like the add rule.
///
/// Every device keeps its own ledger next to its local list (UserDefaults on the phone,
/// `AppSettings` on the Mac) and the carrier holds one too (`VocabularyRecord.wordLedger`).
/// The local copy is what makes the merge safe against CloudKit itself: when two devices
/// both rewrite the carrier, CloudKit keeps one, but each device's own ledger still holds
/// its word and puts it back on the next sync.
struct VocabularyLedger: Codable, Equatable {
    struct Entry: Codable, Equatable {
        /// The spelling from the latest add.
        var word: String
        var addedAt: Date
        var removedAt: Date?

        var isPresent: Bool { removedAt.map { addedAt > $0 } ?? true }
    }

    /// Lowercased word → entry.
    var entries: [String: Entry] = [:]

    private static func key(_ word: String) -> String {
        word.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    /// A ledger for a list that existed before ledgers did: every word added at `stamp`.
    static func seeded(from words: [String], at stamp: Date) -> VocabularyLedger {
        var ledger = VocabularyLedger()
        for word in words {
            let k = key(word)
            guard !k.isEmpty, ledger.entries[k] == nil else { continue }
            ledger.entries[k] = Entry(word: word, addedAt: stamp, removedAt: nil)
        }
        return ledger
    }

    mutating func add(_ word: String, at date: Date) {
        let k = Self.key(word)
        guard !k.isEmpty else { return }
        var entry = entries[k] ?? Entry(word: word, addedAt: date, removedAt: nil)
        entry.word = word
        entry.addedAt = max(entry.addedAt, date)
        entries[k] = entry
    }

    mutating func remove(_ word: String, at date: Date) {
        let k = Self.key(word)
        guard var entry = entries[k] else {
            entries[k] = Entry(word: word, addedAt: .distantPast, removedAt: date)
            return
        }
        entry.removedAt = max(entry.removedAt ?? .distantPast, date)
        entries[k] = entry
    }

    /// Records the change from `old` to `new` as adds and removals at `date` (a whole-list
    /// save, e.g. `CustomVocabularyStore.save`).
    mutating func record(from old: [String], to new: [String], at date: Date) {
        let newKeys = Set(new.map(Self.key))
        let oldKeys = Set(old.map(Self.key))
        for word in old where !newKeys.contains(Self.key(word)) { remove(word, at: date) }
        for word in new where !oldKeys.contains(Self.key(word)) || !(entries[Self.key(word)]?.isPresent ?? false) {
            add(word, at: date)
        }
    }

    /// Entry-wise merge: latest add (and its spelling), latest removal. Commutative, so every
    /// device reaches the same ledger whatever order the syncs arrive in.
    func merged(with other: VocabularyLedger) -> VocabularyLedger {
        var out = self
        for (k, theirs) in other.entries {
            guard let mine = out.entries[k] else { out.entries[k] = theirs; continue }
            let later = theirs.addedAt > mine.addedAt
                || (theirs.addedAt == mine.addedAt && theirs.word < mine.word)
            let removed = [mine.removedAt, theirs.removedAt].compactMap { $0 }.max()
            out.entries[k] = Entry(word: later ? theirs.word : mine.word,
                                   addedAt: max(mine.addedAt, theirs.addedAt),
                                   removedAt: removed)
        }
        return out
    }

    /// The present words, keeping `order`'s order for the words it already holds (so a
    /// device's list doesn't reshuffle on every sync) and appending the rest oldest-add first.
    func words(keepingOrderOf order: [String]) -> [String] {
        var out: [String] = []
        var seen = Set<String>()
        for word in order {
            let k = Self.key(word)
            guard let entry = entries[k], entry.isPresent, seen.insert(k).inserted else { continue }
            out.append(entry.word)
        }
        let rest = entries.filter { $0.value.isPresent && !seen.contains($0.key) }
            .sorted { ($0.value.addedAt, $0.key) < ($1.value.addedAt, $1.key) }
        out.append(contentsOf: rest.map(\.value.word))
        return out
    }

    // MARK: - Carrier / store encoding (empty Data = no ledger yet)

    static func decode(_ data: Data?) -> VocabularyLedger? {
        guard let data, !data.isEmpty else { return nil }
        return try? JSONDecoder().decode(VocabularyLedger.self, from: data)
    }

    func encoded() -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        return (try? encoder.encode(self)) ?? Data()
    }
}
