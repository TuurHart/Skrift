import Foundation

/// A speaker voice profile for diarization. Multi-embedding, NEVER averaged —
/// matching is max-cosine over the list (AirPods vs phone mic stay distinct).
/// `vector` is `[Double]` to match the RN `number[]` and survive JSON round-trips
/// exactly (so a re-sync never treats the same embedding as new). Synced verbatim
/// with the Mac (opaque pass-through there).
struct VoiceEmbedding: Codable, Equatable, Sendable {
    var vector: [Double]
    var condition: String? = nil
    var addedAt: String? = nil
}

/// A person in the names DB. On-disk schema mirrors `backend/utils/names_store.py`
/// and the RN `Person` (`Mobile/lib/names.ts`). Encoding is contract-faithful:
/// `short` is always written (null when empty), `voiceEmbeddings` is omitted when
/// empty, and `deleted` is written only for tombstones.
struct Person: Codable, Equatable, Sendable {
    var canonical: String          // always [[Name]]
    var aliases: [String]
    var short: String?
    var voiceEmbeddings: [VoiceEmbedding]?
    var lastModifiedAt: String     // ISO-8601
    var deleted: Bool?             // tombstone; nil/false = live

    var isDeleted: Bool { deleted == true }

    init(
        canonical: String,
        aliases: [String] = [],
        short: String? = nil,
        voiceEmbeddings: [VoiceEmbedding]? = nil,
        lastModifiedAt: String,
        deleted: Bool? = nil
    ) {
        self.canonical = canonical
        self.aliases = aliases
        self.short = short
        self.voiceEmbeddings = voiceEmbeddings
        self.lastModifiedAt = lastModifiedAt
        self.deleted = deleted
    }

    enum CodingKeys: String, CodingKey {
        case canonical, aliases, short, voiceEmbeddings, lastModifiedAt, deleted
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        canonical = try c.decode(String.self, forKey: .canonical)
        aliases = (try? c.decode([String].self, forKey: .aliases)) ?? []
        short = try c.decodeIfPresent(String.self, forKey: .short)
        voiceEmbeddings = try c.decodeIfPresent([VoiceEmbedding].self, forKey: .voiceEmbeddings)
        lastModifiedAt = (try? c.decode(String.self, forKey: .lastModifiedAt)) ?? ""
        deleted = try c.decodeIfPresent(Bool.self, forKey: .deleted)
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(canonical, forKey: .canonical)
        try c.encode(aliases, forKey: .aliases)
        if let short { try c.encode(short, forKey: .short) } else { try c.encodeNil(forKey: .short) }
        if let v = voiceEmbeddings, !v.isEmpty { try c.encode(v, forKey: .voiceEmbeddings) }
        try c.encode(lastModifiedAt, forKey: .lastModifiedAt)
        if deleted == true { try c.encode(true, forKey: .deleted) }
    }
}

/// The full names file. Top-level `lastModifiedAt` = max of all per-entry
/// timestamps (recomputed on every write); the phone uses it for the cheap
/// pre-sync meta check.
struct NamesData: Codable, Equatable, Sendable {
    var lastModifiedAt: String
    var people: [Person]
}

/// Pure, deterministic names-merge logic (no IO / network), ported from the RN
/// `Mobile/lib/names.ts`. Kept side-effect-free so the unit tests can verify the
/// load-bearing LWW + voiceEmbeddings-union behavior without a backend.
enum NamesMerge {
    static func normaliseCanonical(_ c: String) -> String {
        let s = c.trimmingCharacters(in: .whitespacesAndNewlines)
        if s.hasPrefix("[[") && s.hasSuffix("]]") { return s }
        return s.isEmpty ? "" : "[[\(s)]]"
    }

    private static func keyName(_ canonical: String) -> String {
        (canonical.hasPrefix("[[") && canonical.hasSuffix("]]"))
            ? String(canonical.dropFirst(2).dropLast(2)) : canonical
    }

    /// Max per-entry timestamp, or now if there are no entries.
    static func topLevelTimestamp(_ people: [Person]) -> String {
        let ts = people.map(\.lastModifiedAt).filter { !$0.isEmpty }
        return ts.sorted().last ?? ISO8601.now()
    }

    static func sortPeople(_ people: [Person]) -> [Person] {
        people.sorted {
            keyName($0.canonical).localizedCaseInsensitiveCompare(keyName($1.canonical)) == .orderedAscending
        }
    }

    /// Union two embedding lists, de-duplicated by vector. Returns nil when empty
    /// so we never write `[]` to names.json.
    static func unionEmbeddings(_ a: [VoiceEmbedding]?, _ b: [VoiceEmbedding]?) -> [VoiceEmbedding]? {
        var out: [VoiceEmbedding] = []
        for e in (a ?? []) + (b ?? []) {
            guard !e.vector.isEmpty else { continue }
            if out.contains(where: { $0.vector == e.vector }) { continue }
            out.append(e)
        }
        return out.isEmpty ? nil : out
    }

    /// Per-canonical last-write-wins. Scalar fields: newer `lastModifiedAt` wins,
    /// ties default to remote. `voiceEmbeddings` are ADDITIVE — unioned across
    /// both sides regardless of which scalar version won, so an enrollment on one
    /// device is never clobbered by a newer name edit on the other.
    static func mergeByCanonical(local localPeople: [Person], remote remotePeople: [Person]) -> [Person] {
        var localBy: [String: Person] = [:]
        for p in localPeople where !p.canonical.isEmpty { localBy[p.canonical] = p }
        var remoteBy: [String: Person] = [:]
        for r in remotePeople where !r.canonical.isEmpty { remoteBy[r.canonical] = r }

        var out: [Person] = []
        var seen = Set<String>()
        for canonical in localPeople.map(\.canonical) + remotePeople.map(\.canonical) {
            guard !canonical.isEmpty, !seen.contains(canonical) else { continue }
            seen.insert(canonical)
            let local = localBy[canonical]
            let remote = remoteBy[canonical]

            var winner: Person
            if local == nil {
                winner = remote!
            } else if remote == nil {
                winner = local!
            } else if local!.lastModifiedAt.isEmpty
                || (!remote!.lastModifiedAt.isEmpty && remote!.lastModifiedAt >= local!.lastModifiedAt) {
                winner = remote!
            } else {
                winner = local!
            }

            winner.voiceEmbeddings = unionEmbeddings(local?.voiceEmbeddings, remote?.voiceEmbeddings)
            out.append(winner)
        }
        return out
    }
}
