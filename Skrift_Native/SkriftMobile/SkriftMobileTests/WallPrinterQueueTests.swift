import XCTest
@testable import SkriftMobile

/// Q224: the drain must not drop a card enqueued while a print is awaited, and the
/// queue/ledger persist through the stored-property didSets.
@MainActor
final class WallPrinterQueueTests: XCTestCase {

    private func freshDefaults() -> UserDefaults {
        let name = "WallPrinterQueueTests-\(UUID().uuidString)"
        let d = UserDefaults(suiteName: name)!
        d.removePersistentDomain(forName: name)
        return d
    }

    private func orange(_ title: String) -> Memo {
        Memo.make(title: title, transcript: "t", transcriptStatus: .done, significance: 0.9)
    }

    func testEnqueueDuringDrainSurvives() async {
        let defaults = freshDefaults()
        let wall = WallPrinter(defaults: defaults)
        let first = orange("first"), second = orange("second")
        XCTAssertTrue(wall.enqueue(first))

        await wall.drain(memosByID: [first.id: first]) { memo in
            // A rating commit lands while the printer is busy.
            XCTAssertTrue(wall.enqueue(second))
            return memo.id == first.id
        }

        XCTAssertEqual(wall.queue, [second.id.uuidString], "the card enqueued mid-drain was lost")
        XCTAssertEqual(wall.queuedCount, 1)
        XCTAssertNotNil(wall.printedAt(first.id))
        // Persisted, and a new instance reads it back once.
        XCTAssertEqual(defaults.stringArray(forKey: "wallPrintQueue"), [second.id.uuidString])
        XCTAssertEqual(WallPrinter(defaults: defaults).queuedCount, 1)
        XCTAssertNotNil(WallPrinter(defaults: defaults).printedAt(first.id))
    }

    func testFailedPrintKeepsCardQueuedAndMissingMemoIsDropped() async {
        let wall = WallPrinter(defaults: freshDefaults())
        let kept = orange("kept"), gone = orange("gone")
        wall.enqueue(gone)
        wall.enqueue(kept)

        await wall.drain(memosByID: [kept.id: kept]) { _ in false }

        XCTAssertEqual(wall.queue, [kept.id.uuidString])
        XCTAssertNil(wall.printedAt(kept.id))
    }
}
