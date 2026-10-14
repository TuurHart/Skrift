import Foundation

/// THE `names.json` store — ONE class for both apps (SharedKit wave 2; previously
/// twinned mobile Services/NamesStore.swift vs desktop Pipeline/Sanitisation/
/// NamesStore.swift — load/save/livePeople/addVoiceEmbedding had already been
/// hand-mirrored line-for-line). The on-disk schema mirrors the retired
/// `backend/utils/names_store.py` so the file round-trips verbatim: contract-
/// faithful encoding, recomputed top-level `lastModifiedAt`, smart per-entry
/// timestamp bumps on UI saves, tombstones for deletions, 90-day tombstone
/// pruning. Pure merge math lives in `NamesMerge`; cross-device sync in
/// `NamesCloudSync` (CloudKit) merges into this local source of truth.
final class NamesStore {

    static let shared = NamesStore()

    private let fileURL: URL
    private let encoder: JSONEncoder
    private let decoder = JSONDecoder()

    /// Actor-guard (Q18/C50): every read-modify-write sequence below (load →
    /// mutate → save) takes this lock for its whole span, so a Mac-originated
    /// edit and a phone-originated `addVoiceEmbedding` (called off-main by
    /// `VoiceEnroller`, BUGS D1) can't race and clobber each other.
    private let lock = NSLock()

    /// Last successfully-decoded roster (Q18/C50/D1: "a torn read never
    /// produces an empty roster"). A corrupt on-disk file falls back to this
    /// in memory rather than presenting empty; only a genuinely fresh
    /// install (no file yet, never loaded before) is allowed to be empty.
    private var lastGood: NamesData?

    /// Q362 (perf2 h-shared-data N1): the decoded roster, kept until `names.json` changes. Every
    /// access used to read and JSON-decode the whole file (voice embeddings included) — per note
    /// open, per popover, per sync pass. The stamp is the file's modification time + size + file
    /// number (an atomic write lands a new file), so a write by anything — this store, the sync, a
    /// second process — is seen on the next read.
    private struct FileStamp: Equatable {
        let modified: Date?
        let size: UInt64?
        let fileNumber: UInt?
    }
    private var memo: (stamp: FileStamp, value: NamesData)?
    /// How many times `names.json` was read and decoded from disk (tests read this).
    private(set) var diskDecodes = 0

    private static func stamp(of url: URL) -> FileStamp? {
        guard let a = try? FileManager.default.attributesOfItem(atPath: url.path) else { return nil }
        return FileStamp(modified: a[.modificationDate] as? Date,
                         size: (a[.size] as? NSNumber)?.uint64Value,
                         fileNumber: (a[.systemFileNumber] as? NSNumber)?.uintValue)
    }

    init(fileURL: URL = AppPaths.namesFile) {
        self.fileURL = fileURL
        let e = JSONEncoder()
        e.outputFormatting = [.prettyPrinted, .sortedKeys]
        self.encoder = e
    }

    /// Full file including tombstones (what the phone's `GET /api/names` consumes).
    func load() -> NamesData {
        lock.lock(); defer { lock.unlock() }
        return unlockedLoad()
    }

    /// MUST be called with `lock` already held.
    private func unlockedLoad() -> NamesData {
        if let stamp = Self.stamp(of: fileURL), let memo, memo.stamp == stamp { return memo.value }
        let outcome = SafeJSONStore.load(NamesData.self, from: fileURL, decoder: decoder)
        diskDecodes += 1
        if let value = outcome.value {
            lastGood = value
            // Stamp AFTER the read, so a write that landed in between is never remembered
            // under the older stamp.
            memo = Self.stamp(of: fileURL).map { ($0, value) }
            return value
        }
        memo = nil
        if outcome.wasCorrupt, let cached = lastGood {
            return cached
        }
        // Genuinely missing (fresh install) — the empty roster is real, not adopted-from-corruption.
        let fresh = NamesData(lastModifiedAt: ISO8601.now(), people: [])
        if !outcome.wasCorrupt { lastGood = fresh }
        return fresh
    }

    /// Live people only (tombstones filtered) — for the desktop UI + sanitisation.
    func livePeople() -> [Person] {
        load().people.filter { !$0.isDeleted }
    }

    /// MUST be called with `lock` already held.
    private func unlockedLivePeople() -> [Person] {
        unlockedLoad().people.filter { !$0.isDeleted }
    }

    /// Write verbatim (caller owns merge), recomputing the top-level timestamp and
    /// sorting. Used by the phone-sync `PUT` and internally. Mirrors `write_names`.
    @discardableResult
    func save(_ data: NamesData) -> NamesData {
        lock.lock(); defer { lock.unlock() }
        return unlockedSave(data)
    }

    /// MUST be called with `lock` already held. Atomic write via `SafeJSONStore`
    /// (Q18/C50) — never a torn/partial file on disk — and refreshes `lastGood`
    /// so a subsequent corrupt read still has this write to fall back to.
    private func unlockedSave(_ data: NamesData) -> NamesData {
        let out = NamesData(
            lastModifiedAt: NamesMerge.topLevelTimestamp(data.people),
            people: NamesMerge.sortPeople(data.people)
        )
        let before = Self.stamp(of: fileURL)
        SafeJSONStore.write(out, to: fileURL, encoder: encoder)
        lastGood = out
        // Warm the memo only when the write really landed (a failed write leaves the old stamp).
        if let after = Self.stamp(of: fileURL), after != before { memo = (after, out) } else { memo = nil }
        return out
    }

    /// Desktop UI save (`POST /api/config/names`): bump `lastModifiedAt` only for
    /// entries that actually changed, tombstone any that were removed, and carry
    /// forward voiceEmbeddings the UI doesn't round-trip. Mirrors
    /// `write_with_smart_bumps`.
    @discardableResult
    func writeWithSmartBumps(_ newPeople: [Person]) -> NamesData {
        lock.lock(); defer { lock.unlock() }
        return unlockedWriteWithSmartBumps(newPeople)
    }

    /// MUST be called with `lock` already held.
    private func unlockedWriteWithSmartBumps(_ newPeople: [Person]) -> NamesData {
        let existing = unlockedLoad()
        var existingByCanonical: [String: Person] = [:]
        for p in existing.people where !p.isDeleted { existingByCanonical[p.canonical] = p }

        var normalised: [Person] = []
        var incoming = Set<String>()
        let now = ISO8601.now()

        for raw in newPeople {
            guard var e = normalise(raw) else { continue }
            incoming.insert(e.canonical)
            let prev = existingByCanonical[e.canonical]

            // Never wipe phone-enrolled voice profiles on a desktop name edit.
            if (e.voiceEmbeddings?.isEmpty ?? true), let pv = prev?.voiceEmbeddings, !pv.isEmpty {
                e.voiceEmbeddings = pv
            }

            if let prev, semanticEqual(prev, e) {
                e.lastModifiedAt = prev.lastModifiedAt   // unchanged — keep timestamp
            } else {
                e.lastModifiedAt = now
            }
            e.deleted = nil
            normalised.append(e)
        }

        // Deletions: any previously-live canonical not in the incoming set → tombstone.
        for (canonical, prev) in existingByCanonical where !incoming.contains(canonical) {
            normalised.append(Person(
                canonical: canonical,
                aliases: prev.aliases,
                short: prev.short,
                lastModifiedAt: now,
                deleted: true
            ))
        }

        // Preserve pre-existing tombstones (LWW keeps the newer one on next sync).
        for prev in existing.people where prev.isDeleted
            && !incoming.contains(prev.canonical)
            && !normalised.contains(where: { $0.canonical == prev.canonical }) {
            normalised.append(prev)
        }

        return unlockedSave(NamesData(lastModifiedAt: now, people: normalised))
    }

    /// Append a voiceprint to a person (de-duped by vector, union — multi-embedding,
    /// never averaged) and bump `lastModifiedAt` so it syncs; creates the person if new,
    /// seeded with its name as alias (C257). Never revives a tombstone (C259/R63): naming a
    /// deleted person's voice again starts a FRESH person holding only this voiceprint, none
    /// of the deleted one's aliases/short/voiceprints. Alias-SAFE on a live person (never
    /// touches its aliases/short). Mirrors the
    /// phone's `NamesStore.addVoiceEmbedding` — Mac-originated enrollment syncs back.
    func addVoiceEmbedding(canonical: String, embedding: VoiceEmbedding) {
        let c = NamesMerge.normaliseCanonical(canonical)
        guard !c.isEmpty, !embedding.vector.isEmpty else { return }
        lock.lock(); defer { lock.unlock() }
        var data = unlockedLoad()
        // Same full name = same person (C254): a live row of any case.
        let key = NamesMerge.matchKey(c)
        if let idx = data.people.firstIndex(where: { !$0.isDeleted && NamesMerge.matchKey($0.canonical) == key }) {
            var p = data.people[idx]
            p.voiceEmbeddings = NamesMerge.unionEmbeddings(p.voiceEmbeddings, [embedding]) ?? [embedding]
            p.lastModifiedAt = ISO8601.now()
            data.people[idx] = p
        } else {
            // The fresh row replaces this canonical's tombstone (newer stamp, so it wins LWW).
            data.people.removeAll { $0.isDeleted && $0.canonical == c }
            // C257/R66: an unknown name is born with its typed name as the alias, never `[]`
            // (an alias-less person never links). An existing person is never touched above.
            data.people.append(Person(canonical: c, aliases: PersonEditCore.defaultAliases(forName: c), short: nil,
                                      voiceEmbeddings: [embedding], lastModifiedAt: ISO8601.now()))
        }
        _ = unlockedSave(data)
    }

    /// Add a person by canonical (quick-add flow and tests). NEVER overwrites a live person's
    /// aliases/short (setexp-107: the Add Person sheet used to wipe them): a live person with
    /// the same full name, any case (C254), is MERGED into — new aliases unioned in, short kept —
    /// and the merge is announced (`RosterMergeNotice`). A tombstone is resurrected IN PLACE
    /// (keeping voiceprints) with the given aliases/short. To edit a person deliberately use
    /// `upsert(_:replacing:)`. Returns the surviving canonical when it merged, else nil.
    @discardableResult
    func upsert(canonical: String, aliases: [String], short: String?) -> String? {
        let c = NamesMerge.normaliseCanonical(canonical)
        guard !c.isEmpty else { return nil }
        let mergedInto: String? = {
            lock.lock(); defer { lock.unlock() }
            var data = unlockedLoad()
            let cleanedAliases = aliases.map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
            let cleanedShort = (short?.trimmingCharacters(in: .whitespaces)).flatMap { $0.isEmpty ? nil : $0 }
            let key = NamesMerge.matchKey(c)
            if let idx = data.people.firstIndex(where: { !$0.isDeleted && NamesMerge.matchKey($0.canonical) == key }) {
                // Live person, same full name: union the aliases in, keep their short.
                var p = data.people[idx]
                let union = NamesMerge.unionAliases(p.aliases, cleanedAliases)
                if union != p.aliases {
                    p.aliases = union
                    p.lastModifiedAt = ISO8601.now()
                    data.people[idx] = p
                    _ = unlockedSave(data)
                }
                return p.canonical
            }
            if let idx = data.people.firstIndex(where: { $0.canonical == c }) {
                var p = data.people[idx]
                p.aliases = cleanedAliases
                p.short = cleanedShort
                p.lastModifiedAt = ISO8601.now()
                p.deleted = nil
                data.people[idx] = p
            } else {
                data.people.append(Person(canonical: c, aliases: cleanedAliases, short: cleanedShort, lastModifiedAt: ISO8601.now()))
            }
            _ = unlockedSave(data)
            return nil
        }()
        if let mergedInto { RosterMergeNotice.post(into: mergedInto) }
        return mergedInto
    }

    /// Insert or update ONE person from the detail editor (mocks/opt-in-naming.html panel 3),
    /// matching the existing entry by `replacing` — the ORIGINAL canonical — so a renamed full
    /// name REPLACES the old entry instead of duplicating it. Falls back to matching the new
    /// canonical (a no-rename edit) or appending (a brand-new person). Persists + syncs via
    /// `writeWithSmartBumps` (which also carries forward voiceprints the editor doesn't round-trip).
    /// Same full name = same person (C254): an ADD, or a rename onto another person's full name,
    /// whose name matches a live row case-insensitively MERGES into that row (aliases and
    /// voiceprints unioned, the row's own spelling kept) and announces it (`RosterMergeNotice`).
    /// Returns the surviving canonical when it merged, else nil.
    @discardableResult
    func upsert(_ person: Person, replacing originalCanonical: String?) -> String? {
        let mergedInto: String? = {
            lock.lock(); defer { lock.unlock() }
            var people = unlockedLivePeople()
            let newKey = NamesMerge.matchKey(person.canonical)
            let editIndex = originalCanonical.flatMap { orig in
                people.firstIndex(where: { NamesMerge.matchKey($0.canonical) == NamesMerge.matchKey(orig) })
            }
            let sameName = people.indices.first { $0 != editIndex && NamesMerge.matchKey(people[$0].canonical) == newKey }
            var merged: String?
            if let i = sameName {
                // ADD (or rename) onto an existing person's full name → MERGE rather than clobber
                // or duplicate: union aliases + voiceprints, take a short the add set.
                var into = people[i]
                into.aliases = NamesMerge.unionAliases(into.aliases, person.aliases)
                if let s = person.short, !s.isEmpty { into.short = s }
                into.voiceEmbeddings = NamesMerge.unionEmbeddings(into.voiceEmbeddings, person.voiceEmbeddings)
                people[i] = into
                // A renamed person folds away; `writeWithSmartBumps` tombstones its old canonical.
                if let e = editIndex { people.remove(at: e) }
                merged = into.canonical
            } else if let i = editIndex {
                // An EDIT (incl. rename): full replace, so removing an alias actually takes effect.
                people[i] = person
            } else {
                people.append(person)
            }
            _ = unlockedWriteWithSmartBumps(people)
            return merged
        }()
        if let mergedInto { RosterMergeNotice.post(into: mergedInto) }
        return mergedInto
    }

    /// Seed the roster from `People/` note titles (chunk 2, archive/state-2026-09/NAMING_MODEL.md decision 5).
    /// Each NEW title (no live entry matching its canonical key) becomes a Person whose
    /// canonical = the title — so the exported `[[ ]]` body link resolves to the note
    /// exactly (decision 1) — with derived aliases: the FULL title (always a safe,
    /// distinctive match) plus its first-name token (so opt-out auto-links a bare "Hendri",
    /// risk-tiering willing). An EXISTING person is left untouched: their aliases / short /
    /// voiceprints / grown matching state are the DB's, not the note's. Existence-checked by
    /// canonical key (case-insensitive) so re-seeding is idempotent and can't mint a
    /// duplicate. Persists + syncs the new entries via `writeWithSmartBumps`. Returns the
    /// count added. PRIVACY: titles only, app code, no AI (the scanner reads filenames).
    @discardableResult
    func seedRoster(titles: [String]) -> Int {
        lock.lock(); defer { lock.unlock() }
        let existing = unlockedLivePeople()
        var have = Set(existing.map { NamesMerge.matchKey($0.canonical) })
        var added: [Person] = []
        let now = ISO8601.now()
        for raw in titles {
            let title = raw.trimmingCharacters(in: .whitespaces)
            let k = title.lowercased()
            guard !title.isEmpty, !have.contains(k) else { continue }
            have.insert(k)
            // Aliases: the full title, plus the first-name token when the title is multi-word.
            var aliases = [title]
            if let first = title.split(whereSeparator: \.isWhitespace).first.map(String.init),
               first.caseInsensitiveCompare(title) != .orderedSame {
                aliases.append(first)
            }
            added.append(Person(canonical: NamesMerge.normaliseCanonical(title),
                                 aliases: aliases, short: nil, lastModifiedAt: now))
        }
        guard !added.isEmpty else { return 0 }
        _ = unlockedWriteWithSmartBumps(existing + added)
        return added.count
    }

    /// Tombstone ONE person (detail editor "Delete"). `writeWithSmartBumps` tombstones the
    /// removed canonical (kept for LWW sync) and preserves everyone else.
    func delete(canonical: String) {
        lock.lock(); defer { lock.unlock() }
        let key = NamesMerge.matchKey(canonical)
        let remaining = unlockedLivePeople().filter {
            NamesMerge.matchKey($0.canonical) != key
        }
        _ = unlockedWriteWithSmartBumps(remaining)
    }

    /// Drop tombstones older than `maxAgeDays`. Returns the count pruned.
    @discardableResult
    func pruneOldTombstones(maxAgeDays: Int = 90) -> Int {
        lock.lock(); defer { lock.unlock() }
        let data = unlockedLoad()
        let cutoff = Date().timeIntervalSince1970 - Double(maxAgeDays) * 86_400
        var kept: [Person] = []
        var pruned = 0
        for p in data.people {
            if p.isDeleted,
               let ts = ISO8601.date(from: p.lastModifiedAt)?.timeIntervalSince1970,
               ts < cutoff {
                pruned += 1
                continue
            }
            kept.append(p)
        }
        if pruned > 0 { _ = unlockedSave(NamesData(lastModifiedAt: ISO8601.now(), people: kept)) }
        return pruned
    }

    // MARK: - Helpers

    /// Normalise a person for storage: `[[canonical]]`, trimmed aliases (no blanks),
    /// trimmed `short` (nil when empty). Returns nil if the canonical is empty.
    private func normalise(_ p: Person) -> Person? {
        let canonical = NamesMerge.normaliseCanonical(p.canonical)
        guard !canonical.isEmpty else { return nil }
        var e = p
        e.canonical = canonical
        e.aliases = p.aliases.map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        let short = p.short?.trimmingCharacters(in: .whitespaces)
        e.short = (short?.isEmpty ?? true) ? nil : short
        return e
    }

    /// Equal ignoring `lastModifiedAt` + `deleted` (i.e. canonical, aliases, short,
    /// voiceEmbeddings) — decides whether a UI save actually changed an entry.
    private func semanticEqual(_ a: Person, _ b: Person) -> Bool {
        var x = a; x.lastModifiedAt = ""; x.deleted = nil
        var y = b; y.lastModifiedAt = ""; y.deleted = nil
        return x == y
    }
}
