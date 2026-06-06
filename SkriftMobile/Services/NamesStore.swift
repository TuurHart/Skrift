import Foundation

/// Local `names.json` store + mutators, ported from the RN `Mobile/lib/names.ts`.
/// The on-disk schema mirrors `backend/utils/names_store.py` so the file
/// round-trips verbatim through the Mac sync (incl. tombstones + the recomputed
/// top-level `lastModifiedAt`). The bidirectional sync itself lives in
/// `NamesSync`; this is the local source of truth it merges into.
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

    func load() -> NamesData {
        guard let data = try? Data(contentsOf: fileURL),
              let parsed = try? decoder.decode(NamesData.self, from: data) else {
            return NamesData(lastModifiedAt: ISO8601.now(), people: [])
        }
        return parsed
    }

    /// Direct overwrite (also used by the sync merge once the caller has merged).
    /// Recomputes the top-level timestamp and sorts, matching RN `writeData`.
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

    /// Add or update a person; bumps `lastModifiedAt`. Resurrects a tombstone.
    func upsert(canonical: String, aliases: [String], short: String?) {
        let c = NamesMerge.normaliseCanonical(canonical)
        guard !c.isEmpty else { return }
        var data = load()
        let cleanedAliases = aliases.map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        let cleanedShort = short?.trimmingCharacters(in: .whitespaces).nilIfEmpty
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
        _ = save(data)
    }

    /// Soft-delete: write a tombstone for sync (pruned by the backend after 90 days).
    func delete(canonical: String) {
        let c = NamesMerge.normaliseCanonical(canonical)
        var data = load()
        guard let idx = data.people.firstIndex(where: { $0.canonical == c }) else { return }
        data.people[idx].deleted = true
        data.people[idx].lastModifiedAt = ISO8601.now()
        _ = save(data)
    }

    /// Append a voice reference to a person (de-duplicated by vector). Bumps
    /// `lastModifiedAt` so the addition syncs; resurrects a tombstone if needed.
    /// Multi-embedding, never averaged.
    func addVoiceEmbedding(canonical: String, embedding: VoiceEmbedding) {
        let c = NamesMerge.normaliseCanonical(canonical)
        guard !c.isEmpty, !embedding.vector.isEmpty else { return }
        var data = load()
        if let idx = data.people.firstIndex(where: { $0.canonical == c }) {
            var p = data.people[idx]
            p.voiceEmbeddings = NamesMerge.unionEmbeddings(p.voiceEmbeddings, [embedding]) ?? [embedding]
            p.deleted = nil
            p.lastModifiedAt = ISO8601.now()
            data.people[idx] = p
        } else {
            data.people.append(Person(canonical: c, aliases: [], short: nil, voiceEmbeddings: [embedding], lastModifiedAt: ISO8601.now()))
        }
        _ = save(data)
    }

    /// Live people only (tombstones filtered) — for UI.
    func livePeople() -> [Person] {
        load().people.filter { !$0.isDeleted }
    }
}

private extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}
