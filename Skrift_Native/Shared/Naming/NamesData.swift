import Foundation

// Contract-critical names types — the SHARED canonical source compiled into BOTH
// native apps. This file lives in `Skrift_Native/Shared/Naming/` and is referenced
// by SkriftMobile AND SkriftDesktop via each `project.yml`'s `sources:`, so there is
// exactly ONE physical copy: the on-disk schema + JSON encoding can never drift
// between the phone and the Mac (it round-trips byte-for-byte through the sync
// contract). It compiles into each app's OWN module (no separate Swift package), so
// existing call sites need no `import`. (Was hand-duplicated per app until the
// standalone Phase 0, 2026-06-17 — that duplication was a latent drift risk, now
// collapsed to this one source.)

/// A speaker voice profile for diarization. Multi-embedding, NEVER averaged —
/// matching is max-cosine over the list (AirPods vs phone mic stay distinct).
/// `vector` is `[Double]` to match the RN `number[]` and survive JSON round-trips
/// exactly (so a re-sync never treats the same embedding as new). Synced verbatim
/// across phone↔Mac (opaque pass-through on both sides).
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

    /// The bare name for display / as a `**Name:**` turn label (canonical without `[[ ]]`).
    var displayName: String {
        (canonical.hasPrefix("[[") && canonical.hasSuffix("]]"))
            ? String(canonical.dropFirst(2).dropLast(2)) : canonical
    }

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

    init(lastModifiedAt: String, people: [Person]) {
        self.lastModifiedAt = lastModifiedAt
        self.people = people
    }

    enum CodingKeys: String, CodingKey { case lastModifiedAt, people }

    /// Tolerant decode: legacy `names.json` files (pre-timestamped schema) omit
    /// the top-level `lastModifiedAt`. Default it instead of failing the whole
    /// decode — otherwise `NamesStore.load()` silently swallows the error and
    /// reads ZERO people, so name-linking quietly does nothing on real data.
    /// (The Python backend migrates these on read; this mirrors that leniency.)
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        lastModifiedAt = (try? c.decode(String.self, forKey: .lastModifiedAt)) ?? ""
        people = (try? c.decode([Person].self, forKey: .people)) ?? []
    }
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

    static func keyName(_ canonical: String) -> String {
        (canonical.hasPrefix("[[") && canonical.hasSuffix("]]"))
            ? String(canonical.dropFirst(2).dropLast(2)) : canonical
    }

    /// The bare, trimmed name of a canonical (`[[Tiuri Hartog]]` → `Tiuri Hartog`).
    static func bareName(_ canonical: String) -> String {
        keyName(canonical).trimmingCharacters(in: .whitespaces)
    }

    /// The case-insensitive key two canonicals are compared by: `bareName`, lowercased.
    static func matchKey(_ canonical: String) -> String {
        bareName(canonical).lowercased()
    }

    /// The alias-side key (an alias as typed or spoken, trimmed + lowercased) — the same
    /// fold as `matchKey`, for text that carries no `[[ ]]`.
    static func aliasKey(_ alias: String) -> String {
        alias.trimmingCharacters(in: .whitespaces).lowercased()
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

    /// Per-canonical last-write-wins, then same-name folding (C254). Scalar fields: newer
    /// `lastModifiedAt` wins, ties default to remote. `voiceEmbeddings` are ADDITIVE — unioned
    /// across both LIVE sides regardless of which scalar version won, so an enrollment on one
    /// device is never clobbered by a newer name edit on the other. A winning tombstone
    /// carries no voiceprints, and a tombstone never contributes any (C259). Two LIVE rows whose full
    /// names differ only in case are one person: they fold into one row (see `mergeReporting`).
    static func mergeByCanonical(local localPeople: [Person], remote remotePeople: [Person]) -> [Person] {
        mergeReporting(local: localPeople, remote: remotePeople).people
    }

    /// `mergeByCanonical` plus the canonicals that absorbed a same-name case variant, so the
    /// caller can say so ("Merged into John Smith", R62).
    static func mergeReporting(local localPeople: [Person], remote remotePeople: [Person])
        -> (people: [Person], mergedInto: [String]) {
        foldSameName(lwwByCanonical(local: localPeople, remote: remotePeople))
    }

    /// Stage 1: per exact canonical last-write-wins (the original contract merge).
    private static func lwwByCanonical(local localPeople: [Person], remote remotePeople: [Person]) -> [Person] {
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

            // C259/R63: a tombstone carries nothing. A deletion that wins drops every voiceprint,
            // and a losing tombstone (legacy rows may still hold some) contributes none.
            winner.voiceEmbeddings = winner.isDeleted ? nil : unionEmbeddings(
                local.flatMap { $0.isDeleted ? nil : $0.voiceEmbeddings },
                remote.flatMap { $0.isDeleted ? nil : $0.voiceEmbeddings })
            out.append(winner)
        }
        return out
    }

    /// Stage 2 (C254): LIVE rows sharing a `matchKey` fold into one, at the first one's place.
    /// The newest row wins canonical spelling + short + timestamp (ties: the smaller canonical,
    /// so every device picks the same one); aliases and voiceprints are unioned. Tombstones are
    /// left alone — a deletion only ever removes its own exact canonical.
    private static func foldSameName(_ people: [Person]) -> (people: [Person], mergedInto: [String]) {
        var liveByKey: [String: [Person]] = [:]
        for p in people where !p.isDeleted { liveByKey[matchKey(p.canonical), default: []].append(p) }
        guard liveByKey.values.contains(where: { $0.count > 1 }) else { return (people, []) }

        var out: [Person] = []
        var mergedInto: [String] = []
        var emitted = Set<String>()
        for p in people {
            guard !p.isDeleted else { out.append(p); continue }
            let key = matchKey(p.canonical)
            guard let group = liveByKey[key], group.count > 1 else { out.append(p); continue }
            guard !emitted.contains(key) else { continue }
            emitted.insert(key)
            let folded = foldGroup(group)
            out.append(folded)
            mergedInto.append(folded.canonical)
        }
        return (out, mergedInto)
    }

    /// One row out of several live same-name rows (see `foldSameName`).
    static func foldGroup(_ group: [Person]) -> Person {
        var winner = group.max { a, b in
            a.lastModifiedAt != b.lastModifiedAt ? a.lastModifiedAt < b.lastModifiedAt : a.canonical > b.canonical
        }!
        winner.aliases = unionAliases(winner.aliases, group.flatMap(\.aliases))
        winner.voiceEmbeddings = group.reduce(nil as [VoiceEmbedding]?) { unionEmbeddings($0, $1.voiceEmbeddings) }
        winner.deleted = nil
        return winner
    }

    /// `base`, then each alias of `more` not already there (trimmed, case-insensitive, no blanks).
    static func unionAliases(_ base: [String], _ more: [String]) -> [String] {
        var out: [String] = []
        for a in (base + more).map({ $0.trimmingCharacters(in: .whitespaces) }) where !a.isEmpty {
            if !out.contains(where: { aliasKey($0) == aliasKey(a) }) { out.append(a) }
        }
        return out
    }
}
