import XCTest
@testable import SkriftMobile

/// The contract-critical names logic: per-canonical last-write-wins with an
/// ADDITIVE voiceEmbeddings union. The union bug (backend `542e9f0`) wiped
/// phone-enrolled voice profiles — these lock the behavior down deterministically.
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
        // Local has a NEWER scalar edit but only remote carries an enrollment.
        // The union must keep the remote embedding even though local won scalars.
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

    func testMergeUnionsDisjointPeople() {
        let a = Person(canonical: "[[A]]", lastModifiedAt: "2026-06-01T10:00:00.000Z")
        let b = Person(canonical: "[[B]]", lastModifiedAt: "2026-06-02T10:00:00.000Z")
        let merged = NamesMerge.mergeByCanonical(local: [a], remote: [b])
        XCTAssertEqual(Set(merged.map(\.canonical)), ["[[A]]", "[[B]]"])
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
        XCTAssertEqual(tombJSON["deleted"] as? Bool, true)        // present for tombstones
        XCTAssertTrue(tombJSON.keys.contains("voiceEmbeddings"))  // present when non-empty
        XCTAssertEqual(tombJSON["short"] as? String, "Bob")
    }
}

/// `NamesStore` (local names.json) CRUD: upsert/delete tombstones and the
/// additive voiceEmbeddings union. Cross-device convergence rides CloudKit
/// (`NamesCloudSync`) and the pure merge (`NamesMergeTests` above).
final class NamesStoreTests: XCTestCase {

    private func tempStore() -> NamesStore {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("names_\(UUID().uuidString).json")
        return NamesStore(fileURL: url)
    }

    func testUpsertDeleteTombstoneAndResurrect() {
        let store = tempStore()
        store.upsert(canonical: "Nick", aliases: ["Nicky", " "], short: " Nick ")
        var people = store.load().people
        XCTAssertEqual(people.count, 1)
        XCTAssertEqual(people[0].aliases, ["Nicky"])   // blanks trimmed
        XCTAssertEqual(people[0].short, "Nick")        // trimmed

        store.delete(canonical: "Nick")
        XCTAssertTrue(store.load().people[0].isDeleted)
        XCTAssertTrue(store.livePeople().isEmpty)      // tombstone hidden from UI

        store.upsert(canonical: "Nick", aliases: ["Nick"], short: nil)
        people = store.load().people
        XCTAssertFalse(people[0].isDeleted)            // resurrected
    }

    func testAddVoiceEmbeddingUnionsAndDedups() {
        let store = tempStore()
        store.addVoiceEmbedding(canonical: "Jane", embedding: VoiceEmbedding(vector: [1, 2]))
        store.addVoiceEmbedding(canonical: "Jane", embedding: VoiceEmbedding(vector: [1, 2])) // dup
        store.addVoiceEmbedding(canonical: "Jane", embedding: VoiceEmbedding(vector: [3, 4]))
        let jane = store.load().people.first { $0.canonical == "[[Jane]]" }
        XCTAssertEqual(jane?.voiceEmbeddings?.count, 2)
    }
}
