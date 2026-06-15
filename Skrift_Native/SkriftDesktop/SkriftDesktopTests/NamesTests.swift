import XCTest
import Foundation

/// Contract-critical names logic: per-canonical last-write-wins with an ADDITIVE
/// voiceEmbeddings union, plus contract-faithful JSON encoding. Mirrors the iOS
/// rewrite's NamesMergeTests so both sides of the sync stay byte-compatible.
final class NamesMergeTests: XCTestCase {

    func testNormaliseCanonical() {
        XCTAssertEqual(NamesMerge.normaliseCanonical("Nick"), "[[Nick]]")
        XCTAssertEqual(NamesMerge.normaliseCanonical("  [[Jane Doe]] "), "[[Jane Doe]]")
        XCTAssertEqual(NamesMerge.normaliseCanonical("   "), "")
    }

    func testUnionEmbeddingsDedupAndNilWhenEmpty() {
        XCTAssertNil(NamesMerge.unionEmbeddings(nil, nil))
        XCTAssertNil(NamesMerge.unionEmbeddings([], []))
        let a = VoiceEmbedding(vector: [1, 2, 3], condition: "phone-mic")
        let b = VoiceEmbedding(vector: [1, 2, 3], condition: "airpods") // same vector → dup
        let c = VoiceEmbedding(vector: [4, 5, 6])
        let union = NamesMerge.unionEmbeddings([a], [b, c])
        XCTAssertEqual(union?.count, 2)
        XCTAssertEqual(union?.first?.vector, [1, 2, 3])
    }

    func testMergeLocalNewerWinsScalars() {
        let local = Person(canonical: "[[Nick]]", aliases: ["Nicky"], short: "Nick", lastModifiedAt: "2026-06-06T10:00:00.000Z")
        let remote = Person(canonical: "[[Nick]]", aliases: ["N"], short: "N", lastModifiedAt: "2026-06-05T10:00:00.000Z")
        let merged = NamesMerge.mergeByCanonical(local: [local], remote: [remote])
        XCTAssertEqual(merged.count, 1)
        XCTAssertEqual(merged[0].aliases, ["Nicky"])
    }

    func testMergeRemoteNewerWinsScalars() {
        let local = Person(canonical: "[[Nick]]", aliases: ["Nicky"], short: "Nick", lastModifiedAt: "2026-06-05T10:00:00.000Z")
        let remote = Person(canonical: "[[Nick]]", aliases: ["N"], short: "N", lastModifiedAt: "2026-06-06T10:00:00.000Z")
        let merged = NamesMerge.mergeByCanonical(local: [local], remote: [remote])
        XCTAssertEqual(merged[0].aliases, ["N"])
    }

    func testMergeTieFavorsRemote() {
        let same = "2026-06-06T10:00:00.000Z"
        let local = Person(canonical: "[[Nick]]", aliases: ["L"], lastModifiedAt: same)
        let remote = Person(canonical: "[[Nick]]", aliases: ["R"], lastModifiedAt: same)
        let merged = NamesMerge.mergeByCanonical(local: [local], remote: [remote])
        XCTAssertEqual(merged[0].aliases, ["R"])
    }

    func testMergeUnionsVoiceEmbeddingsAcrossWinningSide() {
        let phone = VoiceEmbedding(vector: [0.1, 0.2], condition: "phone-mic")
        let airpods = VoiceEmbedding(vector: [0.3, 0.4], condition: "airpods")
        let local = Person(canonical: "[[Jane]]", aliases: ["Janey"], short: "Jane",
                           voiceEmbeddings: [phone], lastModifiedAt: "2026-06-06T12:00:00.000Z")
        let remote = Person(canonical: "[[Jane]]", aliases: ["J"], short: "J",
                            voiceEmbeddings: [airpods], lastModifiedAt: "2026-06-01T12:00:00.000Z")
        let merged = NamesMerge.mergeByCanonical(local: [local], remote: [remote])
        XCTAssertEqual(merged[0].aliases, ["Janey"])           // local scalars won
        XCTAssertEqual(merged[0].voiceEmbeddings?.count, 2)    // but BOTH embeddings survive
    }

    func testMergeNewerTombstoneWins() {
        let liveLocal = Person(canonical: "[[Bob]]", aliases: ["Bobby"], lastModifiedAt: "2026-06-01T10:00:00.000Z")
        let tombRemote = Person(canonical: "[[Bob]]", lastModifiedAt: "2026-06-06T10:00:00.000Z", deleted: true)
        let merged = NamesMerge.mergeByCanonical(local: [liveLocal], remote: [tombRemote])
        XCTAssertTrue(merged[0].isDeleted)
    }

    func testPersonEncodingIsContractFaithful() throws {
        let encoder = JSONEncoder()

        let live = Person(canonical: "[[Nick]]", aliases: ["Nicky"], short: nil,
                          lastModifiedAt: "2026-06-06T10:00:00.000Z")
        let liveJSON = try JSONSerialization.jsonObject(with: encoder.encode(live)) as! [String: Any]
        XCTAssertEqual(liveJSON["canonical"] as? String, "[[Nick]]")
        XCTAssertTrue(liveJSON.keys.contains("short"))            // always present...
        XCTAssertTrue(liveJSON["short"] is NSNull)                // ...as null
        XCTAssertFalse(liveJSON.keys.contains("voiceEmbeddings")) // omitted when empty
        XCTAssertFalse(liveJSON.keys.contains("deleted"))         // omitted when live

        let tomb = Person(canonical: "[[Bob]]", aliases: [], short: "Bob",
                          voiceEmbeddings: [VoiceEmbedding(vector: [0.5])],
                          lastModifiedAt: "2026-06-06T10:00:00.000Z", deleted: true)
        let tombJSON = try JSONSerialization.jsonObject(with: encoder.encode(tomb)) as! [String: Any]
        XCTAssertEqual(tombJSON["deleted"] as? Bool, true)
        XCTAssertTrue(tombJSON.keys.contains("voiceEmbeddings"))
        XCTAssertEqual(tombJSON["short"] as? String, "Bob")
    }
}

/// The desktop's source-of-truth `NamesStore` — smart bumps, tombstones, prune.
/// Mirrors `backend/utils/names_store.py` behavior against a temp file.
final class NamesStoreTests: XCTestCase {

    private func tempStore() -> NamesStore {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("names_\(UUID().uuidString).json")
        return NamesStore(fileURL: url)
    }

    func testSmartBumpsKeepTimestampForUnchanged() {
        let store = tempStore()
        // Seed with an explicit OLD timestamp so the assertions don't depend on
        // sub-millisecond wall-clock advances between writes.
        let old = "2020-01-01T00:00:00.000Z"
        _ = store.save(NamesData(lastModifiedAt: old, people: [
            Person(canonical: "[[Nick]]", aliases: ["Nicky"], short: "Nick", lastModifiedAt: old)
        ]))

        // Re-save identical data (with blanks to trim) → timestamp must STAY old.
        let unchanged = store.writeWithSmartBumps([
            Person(canonical: "Nick", aliases: ["Nicky", " "], short: " Nick ", lastModifiedAt: "ignored")
        ])
        XCTAssertEqual(unchanged.people[0].aliases, ["Nicky"])   // blanks trimmed
        XCTAssertEqual(unchanged.people[0].short, "Nick")        // trimmed
        XCTAssertEqual(unchanged.people[0].lastModifiedAt, old)  // unchanged → kept

        // Change an alias → timestamp MUST move off the old value.
        let changed = store.writeWithSmartBumps([
            Person(canonical: "[[Nick]]", aliases: ["Nicky", "Nico"], short: "Nick", lastModifiedAt: "ignored")
        ])
        XCTAssertNotEqual(changed.people[0].lastModifiedAt, old)
    }

    func testRemovingAPersonWritesTombstone() {
        let store = tempStore()
        _ = store.writeWithSmartBumps([
            Person(canonical: "Nick", lastModifiedAt: ""),
            Person(canonical: "Jane", lastModifiedAt: ""),
        ])
        // Save without Jane → Jane becomes a tombstone, hidden from livePeople.
        let after = store.writeWithSmartBumps([Person(canonical: "Nick", lastModifiedAt: "")])
        let jane = after.people.first { $0.canonical == "[[Jane]]" }
        XCTAssertEqual(jane?.isDeleted, true)
        XCTAssertEqual(store.livePeople().map(\.canonical), ["[[Nick]]"])
    }

    func testAddVoiceEmbeddingUnionsCreatesAndIsAliasSafe() {
        let store = tempStore()
        // Pre-existing (Mac-aliased) person; enrolling must NOT wipe aliases/short.
        _ = store.save(NamesData(lastModifiedAt: "2026-06-01T00:00:00.000Z", people: [
            Person(canonical: "[[Tiuri Hartog]]", aliases: ["Tuur"], short: "Tiuri",
                   lastModifiedAt: "2026-06-01T00:00:00.000Z")
        ]))
        store.addVoiceEmbedding(canonical: "Tiuri Hartog", embedding: VoiceEmbedding(vector: [1, 2, 3], condition: "voiceloop"))
        store.addVoiceEmbedding(canonical: "Tiuri Hartog", embedding: VoiceEmbedding(vector: [1, 2, 3]))   // dup → no-op
        store.addVoiceEmbedding(canonical: "Tiuri Hartog", embedding: VoiceEmbedding(vector: [4, 5, 6]))
        let tiuri = store.livePeople().first { $0.displayName == "Tiuri Hartog" }
        XCTAssertEqual(tiuri?.aliases, ["Tuur"], "aliases must survive enrollment")
        XCTAssertEqual(tiuri?.short, "Tiuri")
        XCTAssertEqual(tiuri?.voiceEmbeddings?.count, 2)   // union + dedup

        // Brand-new person is created by enrollment.
        store.addVoiceEmbedding(canonical: "[[Roksana]]", embedding: VoiceEmbedding(vector: [7, 8]))
        XCTAssertEqual(store.livePeople().first { $0.displayName == "Roksana" }?.voiceEmbeddings?.count, 1)
    }

    func testSmartBumpsPreserveVoiceEmbeddings() {
        let store = tempStore()
        // Phone enrolled an embedding (simulate by saving directly).
        _ = store.save(NamesData(lastModifiedAt: ISO8601.now(), people: [
            Person(canonical: "[[Jane]]", aliases: ["Janey"], short: "Jane",
                   voiceEmbeddings: [VoiceEmbedding(vector: [0.1, 0.2])],
                   lastModifiedAt: "2026-06-01T00:00:00.000Z")
        ]))
        // Desktop UI saves Jane WITHOUT embeddings (it doesn't round-trip them).
        let after = store.writeWithSmartBumps([
            Person(canonical: "[[Jane]]", aliases: ["Janey"], short: "Jane", lastModifiedAt: "")
        ])
        XCTAssertEqual(after.people[0].voiceEmbeddings?.count, 1)  // not wiped
    }

    func testPruneOldTombstones() {
        let store = tempStore()
        let old = ISO8601.string(from: Date().addingTimeInterval(-100 * 86_400))   // 100 days ago
        let recent = ISO8601.string(from: Date().addingTimeInterval(-10 * 86_400)) // 10 days ago
        _ = store.save(NamesData(lastModifiedAt: ISO8601.now(), people: [
            Person(canonical: "[[Old]]", lastModifiedAt: old, deleted: true),
            Person(canonical: "[[Recent]]", lastModifiedAt: recent, deleted: true),
            Person(canonical: "[[Live]]", lastModifiedAt: recent),
        ]))
        let pruned = store.pruneOldTombstones(maxAgeDays: 90)
        XCTAssertEqual(pruned, 1)
        XCTAssertEqual(Set(store.load().people.map(\.canonical)), ["[[Recent]]", "[[Live]]"])
    }

    // MARK: Detail-editor store ops (upsert / delete — opt-in naming chunk 4)

    func testUpsertAddsThenUpdatesWithoutDuplicating() {
        let store = tempStore()
        store.upsert(Person(canonical: "[[Nick Jansen]]", aliases: ["Nick"], short: "Nick", lastModifiedAt: ""), replacing: nil)
        XCTAssertEqual(store.livePeople().map(\.canonical), ["[[Nick Jansen]]"])
        // Same canonical → replaces in place (no duplicate row).
        store.upsert(Person(canonical: "[[Nick Jansen]]", aliases: ["Nick", "Nicky"], short: "Nick", lastModifiedAt: ""),
                     replacing: "[[Nick Jansen]]")
        XCTAssertEqual(store.livePeople().count, 1)
        XCTAssertEqual(store.livePeople()[0].aliases, ["Nick", "Nicky"])
    }

    func testUpsertRenameReplacesOldAndCarriesVoice() {
        let store = tempStore()
        _ = store.save(NamesData(lastModifiedAt: ISO8601.now(), people: [
            Person(canonical: "[[Nik]]", aliases: ["Nick"], short: "Nick",
                   voiceEmbeddings: [VoiceEmbedding(vector: [0.1, 0.2])], lastModifiedAt: "2026-06-01T00:00:00.000Z")
        ]))
        // Rename the full name, carrying the voiceprints (as PersonEditor does).
        store.upsert(Person(canonical: "[[Nick Jansen]]", aliases: ["Nick"], short: "Nick",
                            voiceEmbeddings: [VoiceEmbedding(vector: [0.1, 0.2])], lastModifiedAt: ""),
                     replacing: "[[Nik]]")
        let live = store.livePeople()
        XCTAssertEqual(live.map(\.canonical), ["[[Nick Jansen]]"], "renamed entry replaces the old one, no dup")
        XCTAssertEqual(live[0].voiceEmbeddings?.count, 1, "voiceprints carried across the rename")
    }

    func testDeleteTombstonesOnePerson() {
        let store = tempStore()
        store.upsert(Person(canonical: "[[Nick Jansen]]", aliases: ["Nick"], lastModifiedAt: ""), replacing: nil)
        store.upsert(Person(canonical: "[[Jane Doe]]", aliases: ["Jane"], lastModifiedAt: ""), replacing: nil)
        store.delete(canonical: "[[Jane Doe]]")
        XCTAssertEqual(store.livePeople().map(\.canonical), ["[[Nick Jansen]]"])
        XCTAssertEqual(store.load().people.first { $0.canonical == "[[Jane Doe]]" }?.isDeleted, true)
    }
}

/// Regression: a real legacy names.json (no top-level / per-entry lastModifiedAt)
/// must still decode. A strict decoder threw → NamesStore silently read ZERO
/// people → name-linking quietly no-op'd. Found by running a real memo with two
/// friends both called "Jack".
final class LegacyNamesDecodeTests: XCTestCase {
    private let legacyJSON = """
    {"people":[
      {"canonical":"[[Jack Hutton]]","aliases":["Jack","Jank"],"short":"jank"},
      {"canonical":"[[Jack Timmons]]","aliases":["Jack"],"short":"timmons"},
      {"canonical":"[[Roksana Gurova]]","aliases":["Rox"],"short":"Rox"}
    ]}
    """

    func testLegacyFileWithoutTimestampsDecodes() throws {
        let data = try JSONDecoder().decode(NamesData.self, from: Data(legacyJSON.utf8))
        XCTAssertEqual(data.people.count, 3)        // was 0 before the tolerant-decode fix
        XCTAssertEqual(data.lastModifiedAt, "")     // defaulted, not a thrown decode error
    }

    func testTwoJacksSurfaceAsAmbiguous() throws {
        let data = try JSONDecoder().decode(NamesData.self, from: Data(legacyJSON.utf8))
        let r = Sanitiser.process(text: "I told Jack about it, then Jack again.", people: data.people)
        XCTAssertFalse(r.sanitised.contains("[["))          // ambiguous → nothing auto-linked
        XCTAssertEqual(r.ambiguous.first?.alias, "jack")
        XCTAssertEqual(r.ambiguous.first?.candidates.count, 2)  // both Jacks offered to the picker
    }
}
