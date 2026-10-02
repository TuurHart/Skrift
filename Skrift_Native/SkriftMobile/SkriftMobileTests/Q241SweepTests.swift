import XCTest
@testable import SkriftMobile

/// Q241 bug 3 (C115, cleanup-audit P54): CloudKit duplicate memo UUIDs land mid-session (the
/// 2026-07-12 crash loop), but `CloudSyncMonitor`'s post-import sweep omitted `MemoDeduper` —
/// the foreground gate was the only mid-session dedupe path. The import pass must dedupe.
@MainActor
final class Q241SweepTests: XCTestCase {

    private func clone(id: UUID, at when: Date) -> Memo {
        Memo(id: id, audioFilename: "memo_\(id.uuidString).m4a", duration: 5,
             recordedAt: when, transcript: "same words")
    }

    func testTheImportSweepTrashesAnExactCloneRow() {
        let repo = NotesRepository(inMemory: true)
        let id = UUID()
        let when = Date(timeIntervalSince1970: 1_000_000)
        repo.insert(clone(id: id, at: when))
        repo.insert(clone(id: id, at: when))
        XCTAssertEqual(repo.allMemos().filter { $0.id == id }.count, 2, "precondition: the dupe landed")

        CloudSyncMonitor.runMemoSweeps(repo)

        XCTAssertEqual(repo.allMemos().filter { $0.id == id }.count, 1,
                       "one keeper stays live after an import — no waiting for the next foreground")
    }
}
