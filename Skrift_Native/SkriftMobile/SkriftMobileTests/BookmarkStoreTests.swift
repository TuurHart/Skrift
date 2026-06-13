import XCTest
@testable import SkriftMobile

final class BookmarkStoreTests: XCTestCase {

    private func tempStore() -> BookmarkStore {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("bm_\(UUID().uuidString)", isDirectory: true)
        return BookmarkStore(directory: dir)
    }

    func testAddLoadSortedByPosition() {
        let store = tempStore(); let id = UUID()
        store.add(AudiobookBookmark(position: 120, chapterLabel: "ch. 3"), bookID: id)
        store.add(AudiobookBookmark(position: 30, chapterLabel: "ch. 1"), bookID: id)
        let list = store.load(bookID: id)
        XCTAssertEqual(list.map(\.position), [30, 120])
        XCTAssertEqual(list.first?.chapterLabel, "ch. 1")
    }

    func testNearDuplicateIsSkipped() {
        let store = tempStore(); let id = UUID()
        store.add(AudiobookBookmark(position: 100), bookID: id)
        store.add(AudiobookBookmark(position: 101), bookID: id)   // within 2s → skipped
        XCTAssertEqual(store.load(bookID: id).count, 1)
        store.add(AudiobookBookmark(position: 105), bookID: id)   // >2s → added
        XCTAssertEqual(store.load(bookID: id).count, 2)
    }

    func testRemoveById() {
        let store = tempStore(); let id = UUID()
        let b = AudiobookBookmark(position: 50)
        store.add(b, bookID: id)
        store.add(AudiobookBookmark(position: 200), bookID: id)
        let after = store.remove(id: b.id, bookID: id)
        XCTAssertEqual(after.map(\.position), [200])
        XCTAssertEqual(store.load(bookID: id).map(\.position), [200])
    }

    func testEmptyWhenMissing() {
        XCTAssertEqual(tempStore().load(bookID: UUID()), [])
    }

    func testIsolatedPerBook() {
        let store = tempStore(); let a = UUID(); let b = UUID()
        store.add(AudiobookBookmark(position: 10), bookID: a)
        XCTAssertEqual(store.load(bookID: a).count, 1)
        XCTAssertEqual(store.load(bookID: b).count, 0)
    }

    func testRoundTripPreservesFields() throws {
        let store = tempStore(); let id = UUID()
        let made = AudiobookBookmark(position: 77.5, chapterLabel: "ch. 2 — X", createdAt: Date(timeIntervalSince1970: 1_000_000))
        store.add(made, bookID: id)
        let back = store.load(bookID: id).first
        XCTAssertEqual(back?.position, 77.5)
        XCTAssertEqual(back?.chapterLabel, "ch. 2 — X")
        XCTAssertEqual(back?.createdAt, Date(timeIntervalSince1970: 1_000_000))
    }
}
