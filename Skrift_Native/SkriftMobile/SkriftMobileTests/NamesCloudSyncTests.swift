import XCTest
import SwiftData
@testable import SkriftMobile

/// Phase 1e: names + enrolled voices sync across the user's devices via a CloudKit
/// `NamesRecord` carrier, reconciled with the local `names.json` through the SAME
/// `NamesMerge` the Mac sync uses (so the contract + `NamesStore` are untouched). The
/// store is in-memory (CloudKit `.none`); each test injects a temp `names.json`.
@MainActor
final class NamesCloudSyncTests: XCTestCase {

    private var tempFile: URL!
    private var store: NamesStore!

    override func setUpWithError() throws {
        tempFile = FileManager.default.temporaryDirectory
            .appendingPathComponent("names_\(UUID().uuidString).json")
        store = NamesStore(fileURL: tempFile)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: tempFile)
    }

    private func person(_ canonical: String, ts: String, embeddings: [VoiceEmbedding]? = nil) -> Person {
        Person(canonical: canonical, lastModifiedAt: ts, deleted: nil).with(embeddings)
    }

    private func recordBlob(_ people: [Person]) -> Data {
        try! JSONEncoder().encode(NamesData(lastModifiedAt: NamesMerge.topLevelTimestamp(people), people: people))
    }

    private func decodeRecord(_ repo: NotesRepository) -> [Person] {
        guard let blob = repo.allNamesRecords().first?.blob,
              let data = try? JSONDecoder().decode(NamesData.self, from: blob) else { return [] }
        return data.people
    }

    func testFirstSyncCreatesCarrierFromLocalNames() {
        let repo = NotesRepository(inMemory: true)
        store.save(NamesData(lastModifiedAt: "", people: [person("[[Tiuri]]", ts: "2026-06-18T10:00:00Z")]))

        NamesCloudSync.run(repo, store: store)

        XCTAssertEqual(repo.allNamesRecords().count, 1)
        XCTAssertEqual(decodeRecord(repo).map(\.canonical), ["[[Tiuri]]"])
    }

    func testRemotePersonMergesIntoLocalFile() {
        let repo = NotesRepository(inMemory: true)
        store.save(NamesData(lastModifiedAt: "", people: [person("[[Tiuri]]", ts: "2026-06-18T10:00:00Z")]))
        // A person that arrived from another device (the synced carrier).
        repo.context.insert(NamesRecord(blob: recordBlob([person("[[Jack]]", ts: "2026-06-18T11:00:00Z")])))
        repo.save()

        NamesCloudSync.run(repo, store: store)

        // Local names.json now has both (sorted), and so does the carrier.
        XCTAssertEqual(store.livePeople().map(\.canonical).sorted(), ["[[Jack]]", "[[Tiuri]]"])
        XCTAssertEqual(decodeRecord(repo).map(\.canonical).sorted(), ["[[Jack]]", "[[Tiuri]]"])
    }

    func testVoiceEmbeddingUnionRidesThrough() {
        let repo = NotesRepository(inMemory: true)
        let local = person("[[Tiuri]]", ts: "2026-06-18T10:00:00Z", embeddings: [VoiceEmbedding(vector: [0.1, 0.2])])
        let remote = person("[[Tiuri]]", ts: "2026-06-18T11:00:00Z", embeddings: [VoiceEmbedding(vector: [0.3, 0.4])])
        store.save(NamesData(lastModifiedAt: "", people: [local]))
        repo.context.insert(NamesRecord(blob: recordBlob([remote])))
        repo.save()

        NamesCloudSync.run(repo, store: store)

        // The enrollment from each "device" survives — union, not LWW-clobber.
        let vectors = (store.load().people.first { $0.canonical == "[[Tiuri]]" }?.voiceEmbeddings ?? []).map(\.vector)
        XCTAssertEqual(Set(vectors), [[0.1, 0.2], [0.3, 0.4]])
    }

    func testIdempotentSingleRecord() {
        let repo = NotesRepository(inMemory: true)
        store.save(NamesData(lastModifiedAt: "", people: [person("[[Tiuri]]", ts: "2026-06-18T10:00:00Z")]))

        NamesCloudSync.run(repo, store: store)
        let blobAfterFirst = repo.allNamesRecords().first?.blob
        NamesCloudSync.run(repo, store: store)

        XCTAssertEqual(repo.allNamesRecords().count, 1, "second run must not duplicate the carrier")
        XCTAssertEqual(repo.allNamesRecords().first?.blob, blobAfterFirst, "stable — no churn on an unchanged set")
    }

    func testCollapsesDuplicateCarriers() {
        let repo = NotesRepository(inMemory: true)
        store.save(NamesData(lastModifiedAt: "", people: [person("[[Tiuri]]", ts: "2026-06-18T10:00:00Z")]))
        // Two devices each created a carrier before they synced.
        repo.context.insert(NamesRecord(blob: recordBlob([person("[[Jack]]", ts: "2026-06-18T11:00:00Z")])))
        repo.context.insert(NamesRecord(blob: recordBlob([person("[[Mary]]", ts: "2026-06-18T12:00:00Z")])))
        repo.save()

        NamesCloudSync.run(repo, store: store)

        XCTAssertEqual(repo.allNamesRecords().count, 1, "duplicate carriers collapse to one")
        XCTAssertEqual(decodeRecord(repo).map(\.canonical).sorted(), ["[[Jack]]", "[[Mary]]", "[[Tiuri]]"])
        XCTAssertEqual(store.livePeople().count, 3, "no person lost in the collapse")
    }
}

private extension Person {
    func with(_ embeddings: [VoiceEmbedding]?) -> Person {
        var p = self
        p.voiceEmbeddings = embeddings
        return p
    }
}
