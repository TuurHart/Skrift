import XCTest
import Foundation

/// Q422 (C259/R63, C208): a deleted person's voiceprints go with the tombstone. Deleting drops
/// them; the `NamesMerge` LWW merge never unions embeddings onto a tombstone (nor lets a losing
/// tombstone contribute any); `addVoiceEmbedding` never revives a tombstone with its old self.
/// Fixture: test-fixtures/corpus/rosters/roster-delete-with-voiceprint.json.
final class RosterTombstoneVoiceprintTests: XCTestCase {

    private struct Fixture: Decodable {
        struct Expect: Decodable {
            let reEnrollVoiceprints: Int
            let untouched: String
            let untouchedVoiceprints: Int
        }
        let existing: NamesData
        let deletes: String
        let remoteLive: NamesData
        let remoteTombstone: NamesData
        let reEnroll: VoiceEmbedding
        let expect: Expect
    }

    private func fixture() throws -> Fixture {
        let url = CorpusSeed.fixtureRoot(file: #filePath)
            .appendingPathComponent("rosters/roster-delete-with-voiceprint.json")
        return try JSONDecoder().decode(Fixture.self, from: Data(contentsOf: url))
    }

    private func store(seeded data: NamesData) -> NamesStore {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("names_q422_\(UUID().uuidString).json")
        let store = NamesStore(fileURL: url)
        _ = store.save(data)
        return store
    }

    private func row(_ canonical: String, in people: [Person]) -> Person? {
        people.first { $0.canonical == canonical }
    }

    private func assertBareTombstone(_ p: Person?, _ what: String, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(p?.isDeleted, true, "\(what): the person stays deleted", file: file, line: line)
        XCTAssertNil(p?.voiceEmbeddings, "\(what): a tombstone carries no voiceprints", file: file, line: line)
    }

    func testDeleteDropsVoiceprintsIntoTheTombstone() throws {
        let f = try fixture()
        let s = store(seeded: f.existing)
        s.delete(canonical: f.deletes)
        let people = s.load().people
        assertBareTombstone(row(f.deletes, in: people), "after delete")
        XCTAssertEqual(row(f.expect.untouched, in: people)?.voiceEmbeddings?.count, f.expect.untouchedVoiceprints)

        // On disk too: the tombstone writes no voiceEmbeddings key.
        let encoded = try JSONEncoder().encode(row(f.deletes, in: people))
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        XCTAssertFalse(json.keys.contains("voiceEmbeddings"))
    }

    // An older carrier still holding the person live (with a voiceprint of its own) must not
    // hand its voiceprints, or the deleted ones, to the newer local tombstone — either direction.
    func testSyncNeverUnionsEmbeddingsOntoTheTombstone() throws {
        let f = try fixture()
        let s = store(seeded: f.existing)
        s.delete(canonical: f.deletes)
        let local = s.load().people
        let a = NamesMerge.mergeByCanonical(local: local, remote: f.remoteLive.people)
        let b = NamesMerge.mergeByCanonical(local: f.remoteLive.people, remote: local)
        assertBareTombstone(row(f.deletes, in: a), "local tombstone vs remote live")
        assertBareTombstone(row(f.deletes, in: b), "remote tombstone vs local live")
        XCTAssertEqual(row(f.expect.untouched, in: a)?.voiceEmbeddings?.count, f.expect.untouchedVoiceprints)

        // The CloudKit reconcile path rides the same merge.
        let blob = try JSONEncoder().encode(f.remoteLive)
        let outcome = try XCTUnwrap(NamesSyncCore.reconcile(
            localPeople: local, records: [NamesRecord(blob: blob)],
            insert: { _ in }, delete: { _ in }))
        assertBareTombstone(row(f.deletes, in: outcome.merged.people), "reconcile")
    }

    // A newer tombstone from another device (a legacy one that still holds a voiceprint) wins
    // over the local live person and arrives bare: the local voiceprints go with it.
    func testNewerTombstoneWinsBare() throws {
        let f = try fixture()
        let a = NamesMerge.mergeByCanonical(local: f.existing.people, remote: f.remoteTombstone.people)
        let b = NamesMerge.mergeByCanonical(local: f.remoteTombstone.people, remote: f.existing.people)
        assertBareTombstone(row(f.deletes, in: a), "remote tombstone newer")
        assertBareTombstone(row(f.deletes, in: b), "local tombstone newer")
    }

    // A tombstone that LOSES (the person was re-added since) contributes none of its voiceprints.
    func testLosingTombstoneContributesNoVoiceprints() throws {
        let f = try fixture()
        var oldTomb = try XCTUnwrap(f.remoteTombstone.people.first)
        oldTomb.lastModifiedAt = "2026-08-01T00:00:00Z"
        let liveBefore = try XCTUnwrap(row(f.deletes, in: f.existing.people))
        let merged = NamesMerge.mergeByCanonical(local: f.existing.people, remote: [oldTomb])
        let live = try XCTUnwrap(row(f.deletes, in: merged))
        XCTAssertFalse(live.isDeleted)
        XCTAssertEqual(live.voiceEmbeddings, liveBefore.voiceEmbeddings, "only the live row's voiceprints")
    }

    // Naming a speaker with the deleted person's name starts a fresh person: only the new
    // voiceprint, none of the deleted row's aliases or voiceprints, and no tombstone left behind.
    func testReEnrollAfterDeleteStartsFreshNotRevived() throws {
        let f = try fixture()
        let s = store(seeded: f.existing)
        s.delete(canonical: f.deletes)
        s.addVoiceEmbedding(canonical: NamesMerge.keyName(f.deletes), embedding: f.reEnroll)
        assertFresh(s.load().people, f)

        // A legacy tombstone that still holds a voiceprint is not revived either.
        let legacy = store(seeded: f.remoteTombstone)
        legacy.addVoiceEmbedding(canonical: NamesMerge.keyName(f.deletes), embedding: f.reEnroll)
        assertFresh(legacy.load().people, f)
    }

    private func assertFresh(_ people: [Person], _ f: Fixture, file: StaticString = #filePath, line: UInt = #line) {
        let rows = people.filter { $0.canonical == f.deletes }
        XCTAssertEqual(rows.count, 1, "one row for the name", file: file, line: line)
        let p = rows.first
        XCTAssertEqual(p?.isDeleted, false, file: file, line: line)
        XCTAssertEqual(p?.voiceEmbeddings, [f.reEnroll], "only the new voiceprint", file: file, line: line)
        XCTAssertFalse(p?.aliases.contains("Marti") ?? true, "the deleted row's aliases stay gone", file: file, line: line)
        XCTAssertEqual(f.expect.reEnrollVoiceprints, p?.voiceEmbeddings?.count, file: file, line: line)
    }
}
