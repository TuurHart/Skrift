import XCTest
import SwiftData
@testable import SkriftMobile

/// C157 / Q487: a purge deletes the note's polish row and every asset, so nothing of the note
/// is left in the cloud store for another device to find.
@MainActor
final class PurgeCascadeTests: XCTestCase {

    private func count<T: PersistentModel>(_ type: T.Type, _ repo: NotesRepository) -> Int {
        (try? repo.context.fetchCount(FetchDescriptor<T>())) ?? -1
    }

    func testPermanentDeleteRemovesEveryPolishRowAndAsset() throws {
        let repo = NotesRepository(inMemory: true)
        let id = UUID(), other = UUID()
        repo.insert(Memo(id: id, audioFilename: ""))
        repo.insert(Memo(id: other, audioFilename: ""))
        // Two polish rows for the doomed note (two writers raced), one for a neighbour.
        repo.context.insert(MemoEnhancement(memoID: id, copyedit: "Mac", enhancedByDeviceID: "mac"))
        repo.context.insert(MemoEnhancement(memoID: id, copyedit: "iPad", enhancedByDeviceID: "ipad"))
        repo.context.insert(MemoEnhancement(memoID: other, copyedit: "Keep", enhancedByDeviceID: "mac"))
        repo.context.insert(MemoAsset(memoID: id, kind: "photo", filename: "a.jpg", blob: Data("x".utf8)))
        repo.context.insert(MemoAsset(memoID: other, kind: "photo", filename: "b.jpg", blob: Data("y".utf8)))
        repo.save()

        repo.permanentlyDelete(try XCTUnwrap(repo.memo(id: id)))

        XCTAssertNil(repo.enhancement(forMemo: id), "no polish row outlives the note")
        XCTAssertTrue(repo.assets(forMemo: id).isEmpty)
        XCTAssertEqual(count(MemoEnhancement.self, repo), 1, "the neighbour keeps its polish")
        XCTAssertEqual(repo.enhancement(forMemo: other)?.copyedit, "Keep")
        XCTAssertEqual(repo.assets(forMemo: other).count, 1)
    }

    func testTheTrashPurgeCascadesToo() throws {
        let repo = NotesRepository(inMemory: true)
        let id = UUID()
        let memo = Memo(id: id, audioFilename: "")
        repo.insert(memo)
        repo.context.insert(MemoEnhancement(memoID: id, copyedit: "Polish", enhancedByDeviceID: "mac"))
        let t0 = Date()
        memo.deletedAt = t0
        memo.trashSeenAt = t0
        repo.save()

        let purged = repo.purgeExpiredTrash(now: t0.addingTimeInterval(TrashPolicy.retention + 1))

        XCTAssertEqual(purged, 1)
        XCTAssertEqual(count(MemoEnhancement.self, repo), 0)
    }
}
