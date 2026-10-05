import XCTest
import SwiftData
@testable import SkriftMobile

/// Q322: `NotesRepository.save()` with nothing to save is a no-op (no persist, no version bump), so
/// closing an unchanged note no longer rebuilds the list. A save that DOES carry a change, including
/// one the context's autosave already wrote, still bumps (data safety: never drop a real change).
@MainActor
final class SaveNoopTests: XCTestCase {

    private func memo(_ text: String = "hello") -> Memo {
        Memo(audioFilename: "a.m4a", recordedAt: Date(), transcript: text, transcriptStatus: .done)
    }

    func testASaveWithNoChangesLeavesTheVersionsAlone() {
        let repo = NotesRepository(inMemory: true)
        repo.insert(memo())                        // a real change first
        let version = repo.memoSetVersion, structure = repo.memoStructureVersion
        repo.save()
        repo.save()
        XCTAssertEqual(repo.memoSetVersion, version, "no changes: no bump")
        XCTAssertEqual(repo.memoStructureVersion, structure)
    }

    func testAFreshRepositorySaveIsANoop() {
        let repo = NotesRepository(inMemory: true)
        let v = repo.memoSetVersion
        repo.save()
        XCTAssertEqual(repo.memoSetVersion, v)
    }

    func testAnEditBumpsTheVersionButNotTheStructureVersion() throws {
        let repo = NotesRepository(inMemory: true)
        let m = memo()
        repo.insert(m)
        let version = repo.memoSetVersion, structure = repo.memoStructureVersion
        m.transcript = "edited body"
        repo.save()
        XCTAssertEqual(repo.memoSetVersion, version + 1)
        XCTAssertEqual(repo.memoStructureVersion, structure, "a plain edit patches its row; it does not rebuild the list")
        let stored = try XCTUnwrap(repo.allMemos().first { $0.id == m.id })
        XCTAssertEqual(stored.transcript, "edited body")
    }

    func testInsertsAndDeletesBumpBothVersions() {
        let repo = NotesRepository(inMemory: true)
        let m = memo()
        repo.context.insert(m)
        var v = repo.memoSetVersion, s = repo.memoStructureVersion
        repo.save()
        XCTAssertEqual(repo.memoSetVersion, v + 1)
        XCTAssertEqual(repo.memoStructureVersion, s + 1)

        v = repo.memoSetVersion; s = repo.memoStructureVersion
        repo.context.delete(m)
        repo.save()
        XCTAssertEqual(repo.memoSetVersion, v + 1, "a delete is a change")
        XCTAssertEqual(repo.memoStructureVersion, s + 1)
        XCTAssertTrue(repo.allMemos().isEmpty)
    }

    /// The main context autosaves: by the time `save()` runs, `hasChanges` can already be false.
    /// A write the context made itself must still count as a change.
    func testAChangeTheContextAlreadySavedStillBumps() {
        let repo = NotesRepository(inMemory: true)
        let m = memo()
        repo.insert(m)
        let version = repo.memoSetVersion
        m.transcript = "autosaved edit"
        try? repo.context.save()                   // what an autosave does
        XCTAssertFalse(repo.context.hasChanges, "precondition: nothing left pending")
        repo.save()
        XCTAssertEqual(repo.memoSetVersion, version + 1, "the version must not skip an edit the context persisted itself")
        repo.save()
        XCTAssertEqual(repo.memoSetVersion, version + 1, "and only once")
    }

    /// A non-Memo row (an asset) is a context change like any other.
    func testAnAssetRowChangeCounts() {
        let repo = NotesRepository(inMemory: true)
        let m = memo()
        repo.insert(m)
        let version = repo.memoSetVersion
        repo.context.insert(MemoAsset(memoID: m.id, kind: "audio", filename: "a.m4a", blob: Data([1, 2, 3])))
        repo.save()
        XCTAssertEqual(repo.memoSetVersion, version + 1)
    }
}
