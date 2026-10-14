import XCTest
@testable import SkriftMobile

/// Q415 (C272 / R85): a manual reprint keeps the note's prior `printedAt` until the
/// reprint itself succeeds. A failed or cancelled reprint must not erase it.
@MainActor
final class WallReprintStampTests: XCTestCase {

    private func freshDefaults() -> UserDefaults {
        let name = "WallReprintStampTests-\(UUID().uuidString)"
        let d = UserDefaults(suiteName: name)!
        d.removePersistentDomain(forName: name)
        return d
    }

    func testFailedReprintKeepsPriorStamp() async {
        let defaults = freshDefaults()
        let wall = WallPrinter(defaults: defaults)
        let memo = Memo.make(title: "reprint", transcript: "t", transcriptStatus: .done, significance: 0.9)
        let memos = [memo.id: memo]

        // First print succeeds and stamps the note.
        XCTAssertTrue(wall.enqueue(memo))
        await wall.drain(memosByID: memos) { _ in true }
        let first = try? XCTUnwrap(wall.printedAt(memo.id))
        XCTAssertNotNil(first)

        // Manual reprint: no saved printer, so the drain returns before printing.
        // The stamp must still be there.
        wall.printCard(memo, repository: NotesRepository(inMemory: true))
        XCTAssertEqual(wall.printedAt(memo.id), first, "printCard erased the stamp before the reprint ran")
        XCTAssertTrue(wall.queue.contains(memo.id.uuidString))

        // Printer hiccup / cancel: still stamped, still queued.
        await wall.drain(memosByID: memos) { _ in false }
        XCTAssertEqual(wall.printedAt(memo.id), first, "a failed reprint lost the prior stamp")
        XCTAssertEqual(WallPrinter(defaults: defaults).printedAt(memo.id), first, "stamp not persisted")
        XCTAssertTrue(wall.queue.contains(memo.id.uuidString))
    }

    func testSuccessfulReprintWritesNewStamp() async throws {
        let wall = WallPrinter(defaults: freshDefaults())
        let memo = Memo.make(title: "reprint", transcript: "t", transcriptStatus: .done, significance: 0.9)
        let memos = [memo.id: memo]
        XCTAssertTrue(wall.enqueue(memo))
        await wall.drain(memosByID: memos) { _ in true }
        let first = try XCTUnwrap(wall.printedAt(memo.id))

        wall.printCard(memo, repository: NotesRepository(inMemory: true))
        try await Task.sleep(nanoseconds: 20_000_000)
        await wall.drain(memosByID: memos) { _ in true }

        let second = try XCTUnwrap(wall.printedAt(memo.id))
        XCTAssertGreaterThan(second, first)
        XCTAssertTrue(wall.queue.isEmpty)
    }
}
