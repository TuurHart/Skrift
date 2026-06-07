import Foundation

/// The desktop's source-of-truth `names.json` store — the Mac side of the phone
/// sync. Mirrors `backend/utils/names_store.py` so the file round-trips verbatim:
/// contract-faithful encoding, recomputed top-level `lastModifiedAt`, smart
/// per-entry timestamp bumps on UI saves, tombstones for deletions, and 90-day
/// tombstone pruning. Pure merge math lives in `NamesMerge`.
final class NamesStore {
    static let shared = NamesStore()

    private let fileURL: URL
    private let encoder: JSONEncoder
    private let decoder = JSONDecoder()

    init(fileURL: URL = AppPaths.namesFile) {
        self.fileURL = fileURL
        let e = JSONEncoder()
        e.outputFormatting = [.prettyPrinted, .sortedKeys]
        self.encoder = e
    }

    /// Full file including tombstones (what the phone's `GET /api/names` consumes).
    func load() -> NamesData {
        guard let data = try? Data(contentsOf: fileURL),
              let parsed = try? decoder.decode(NamesData.self, from: data) else {
            return NamesData(lastModifiedAt: ISO8601.now(), people: [])
        }
        return parsed
    }

    /// Live people only (tombstones filtered) — for the desktop UI + sanitisation.
    func livePeople() -> [Person] {
        load().people.filter { !$0.isDeleted }
    }

    /// Write verbatim (caller owns merge), recomputing the top-level timestamp and
    /// sorting. Used by the phone-sync `PUT` and internally. Mirrors `write_names`.
    @discardableResult
    func save(_ data: NamesData) -> NamesData {
        let out = NamesData(
            lastModifiedAt: NamesMerge.topLevelTimestamp(data.people),
            people: NamesMerge.sortPeople(data.people)
        )
        if let encoded = try? encoder.encode(out) {
            try? encoded.write(to: fileURL)
        }
        return out
    }

    /// Desktop UI save (`POST /api/config/names`): bump `lastModifiedAt` only for
    /// entries that actually changed, tombstone any that were removed, and carry
    /// forward voiceEmbeddings the UI doesn't round-trip. Mirrors
    /// `write_with_smart_bumps`.
    @discardableResult
    func writeWithSmartBumps(_ newPeople: [Person]) -> NamesData {
        let existing = load()
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

        return save(NamesData(lastModifiedAt: now, people: normalised))
    }

    /// Drop tombstones older than `maxAgeDays`. Returns the count pruned.
    @discardableResult
    func pruneOldTombstones(maxAgeDays: Int = 90) -> Int {
        let data = load()
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
        if pruned > 0 { _ = save(NamesData(lastModifiedAt: ISO8601.now(), people: kept)) }
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
