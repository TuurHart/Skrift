import XCTest
@testable import SkriftMobile

/// C269/R82: removing a bookmark removes exactly the ONE nearest the tap (a tie goes to
/// the earlier) and always produces a "Removed 1 bookmark at <time>" notice.
final class BookmarkRemovalTests: XCTestCase {

    private func tempStore() -> BookmarkStore {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("bmrm_\(UUID().uuidString)", isDirectory: true)
        return BookmarkStore(directory: dir)
    }

    /// `bookmark-delete-near-tie`
    func testBookmarkDeleteNearTie() {
        let store = tempStore(); let id = UUID()
        // Two bookmarks inside one tapped line's span, equidistant (±1.5s) from the tap at 100.
        store.add(AudiobookBookmark(position: 98.5), bookID: id)
        store.add(AudiobookBookmark(position: 101.5), bookID: id)
        store.add(AudiobookBookmark(position: 300), bookID: id)
        let span = store.load(bookID: id).filter { $0.position >= 98 && $0.position <= 102 }
        XCTAssertEqual(span.count, 2)

        let removal = store.removeNearest(to: 100, among: span, bookID: id)
        XCTAssertEqual(removal?.removed.position, 98.5, "a tie breaks to the EARLIER bookmark")
        XCTAssertEqual(store.load(bookID: id).map(\.position), [101.5, 300], "exactly one removed")

        // Strictly nearer wins regardless of order.
        let store2 = tempStore(); let id2 = UUID()
        store2.add(AudiobookBookmark(position: 10), bookID: id2)
        store2.add(AudiobookBookmark(position: 13), bookID: id2)
        let r2 = store2.removeNearest(to: 12, bookID: id2)
        XCTAssertEqual(r2?.removed.position, 13)
        XCTAssertEqual(store2.load(bookID: id2).map(\.position), [10])

        // Nothing to remove → nil, nothing touched.
        XCTAssertNil(store2.removeNearest(to: 5, among: [], bookID: id2))
        XCTAssertEqual(store2.load(bookID: id2).count, 1)
    }

    /// `bookmark-swipe-no-confirm`
    func testBookmarkSwipeShowsNotice() {
        let store = tempStore(); let id = UUID()
        let bm = AudiobookBookmark(position: 754)   // 12:34
        store.add(bm, bookID: id)
        store.add(AudiobookBookmark(position: 2000), bookID: id)

        let removal = store.removeOne(id: bm.id, bookID: id)
        XCTAssertEqual(removal?.notice, "Removed 1 bookmark at \(AudiobookTime.clock(754))")
        XCTAssertTrue(removal?.notice.hasPrefix("Removed 1 bookmark at ") == true)
        XCTAssertEqual(removal?.list.map(\.position), [2000])

        // Undo puts it back, in order.
        if let removal {
            let restored = store.restore(removal, bookID: id)
            XCTAssertEqual(restored.map(\.position), [754, 2000])
            XCTAssertEqual(store.load(bookID: id).map(\.position), [754, 2000])
        }

        // An unknown id removes nothing and produces no notice.
        XCTAssertNil(store.removeOne(id: UUID(), bookID: id))
    }
}
