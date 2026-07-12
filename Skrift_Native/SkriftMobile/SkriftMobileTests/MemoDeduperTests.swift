import XCTest
@testable import SkriftMobile

/// The 2026-07-12 crash loop: a CloudKit re-sync materialized duplicate memo
/// UUIDs and the list's id-keyed dictionaries trapped at launch. The deduper
/// trashes exact clones (blob references detached so the purge can't touch the
/// keeper's files) and leaves divergent same-id rows alone.
final class MemoDeduperTests: XCTestCase {

    @MainActor
    private func makeMemo(id: UUID, transcript: String, recordedAt: Date) -> Memo {
        let m = Memo(id: id, audioFilename: "memo_\(id.uuidString).m4a",
                     duration: 5, recordedAt: recordedAt, transcript: transcript)
        var meta = MemoMetadata()
        meta.imageManifest = [ImageManifestEntry(filename: "p.jpg", offsetSeconds: 0)]
        m.metadata = meta
        return m
    }

    @MainActor
    func testExactCloneIsTrashedWithReferencesDetached() {
        let repo = NotesRepository(inMemory: true)
        let id = UUID()
        let when = Date(timeIntervalSince1970: 1_000_000)
        repo.insert(makeMemo(id: id, transcript: "same words", recordedAt: when))
        repo.insert(makeMemo(id: id, transcript: "same words", recordedAt: when))

        MemoDeduper.run(repo)

        let live = repo.allMemos().filter { $0.id == id }
        XCTAssertEqual(live.count, 1, "exactly one keeper stays live")
        XCTAssertEqual(live.first?.transcript, "same words")
        XCTAssertFalse(live.first?.audioFilename.isEmpty ?? true, "the keeper keeps its audio")

        let trashed = repo.allMemosIncludingTrashed().first { $0.id == id && $0.deletedAt != nil }
        XCTAssertNotNil(trashed, "the clone went to the trash, not oblivion")
        XCTAssertEqual(trashed?.audioFilename, "", "blob reference detached — purge can't kill the keeper's audio")
        XCTAssertNil(trashed?.metadata?.imageManifest, "photo references detached too")
    }

    @MainActor
    func testDivergentSameIdRowsAreLeftAlone() {
        let repo = NotesRepository(inMemory: true)
        let id = UUID()
        let when = Date(timeIntervalSince1970: 1_000_000)
        repo.insert(makeMemo(id: id, transcript: "version A", recordedAt: when))
        repo.insert(makeMemo(id: id, transcript: "version B — edited on the iPad", recordedAt: when))

        MemoDeduper.run(repo)

        XCTAssertEqual(repo.allMemos().filter { $0.id == id }.count, 2,
                       "content differs → NEVER auto-delete (the P0 lesson)")
    }

    @MainActor
    func testUniqueMemosUntouched() {
        let repo = NotesRepository(inMemory: true)
        repo.insert(makeMemo(id: UUID(), transcript: "a", recordedAt: Date()))
        repo.insert(makeMemo(id: UUID(), transcript: "b", recordedAt: Date()))

        MemoDeduper.run(repo)

        XCTAssertEqual(repo.allMemos().count, 2)
        XCTAssertTrue(repo.allMemos().allSatisfy { $0.deletedAt == nil })
    }
}
