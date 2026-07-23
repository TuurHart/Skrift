import XCTest
@testable import SkriftMobile

/// Bookmark sync (iPad wave, 2026-07-23): the whole-list-LWW core + the
/// BookmarkStore's LWW stamp semantics (a user edit stamps; adopting a synced
/// list copies the carrier's stamp verbatim — never mints, or two devices
/// ping-pong forever).
final class AudiobookBookmarkSyncTests: XCTestCase {

    private var inserted: [AudiobookBookmarksRecord] = []
    private var deleted: [AudiobookBookmarksRecord] = []
    private let bookID = UUID()

    override func setUp() {
        super.setUp()
        inserted = []; deleted = []
    }

    private func mark(_ pos: TimeInterval) -> AudiobookBookmark {
        AudiobookBookmark(position: pos, chapterLabel: "ch")
    }

    private func record(_ items: [AudiobookBookmark], at stamp: Date,
                        book: UUID? = nil) -> AudiobookBookmarksRecord {
        AudiobookBookmarksRecord(bookID: book ?? bookID,
                                 itemsBlob: (try? JSONEncoder().encode(items)) ?? Data(),
                                 modifiedAt: stamp)
    }

    private func reconcile(local: [AudiobookBookmark], stamp: Date,
                           records: [AudiobookBookmarksRecord]) -> AudiobookBookmarkSyncCore.Outcome {
        AudiobookBookmarkSyncCore.reconcile(
            bookID: bookID, localItems: local, localModifiedAt: stamp, records: records,
            insert: { self.inserted.append($0) },
            delete: { self.deleted.append($0) })
    }

    // MARK: - core LWW

    func testFreshDeviceNoBookmarksMintsNoCarrier() {
        XCTAssertEqual(reconcile(local: [], stamp: .distantPast, records: []), .noop)
        XCTAssertTrue(inserted.isEmpty, "an empty-@-now carrier would wipe the other device's list")
    }

    func testLocalBookmarksWithNoCarrierPush() {
        let stamp = Date(timeIntervalSince1970: 1_000)
        let outcome = reconcile(local: [mark(10)], stamp: stamp, records: [])
        XCTAssertEqual(outcome, .pushedLocal(stamp: stamp, seededLocalStamp: false))
        XCTAssertEqual(inserted.first?.bookID, bookID)
    }

    func testNewerCarrierAdopted() {
        let carrier = record([mark(5), mark(60)], at: Date(timeIntervalSince1970: 9_000))
        let outcome = reconcile(local: [mark(5)], stamp: Date(timeIntervalSince1970: 1_000),
                                records: [carrier])
        guard case .adoptRemote(let items, let ts) = outcome else {
            return XCTFail("expected adoptRemote, got \(outcome)")
        }
        XCTAssertEqual(items.count, 2)
        XCTAssertEqual(ts, Date(timeIntervalSince1970: 9_000))
    }

    func testLocalDeletionPropagates() {
        // Removed the last bookmark locally (real stamp) — the carrier must adopt
        // the EMPTY list, not resurrect.
        let carrier = record([mark(5)], at: Date(timeIntervalSince1970: 1_000))
        let stamp = Date(timeIntervalSince1970: 9_000)
        let outcome = reconcile(local: [], stamp: stamp, records: [carrier])
        XCTAssertEqual(outcome, .pushedLocal(stamp: stamp, seededLocalStamp: false))
        let decoded = try? JSONDecoder().decode([AudiobookBookmark].self, from: carrier.itemsBlob)
        XCTAssertEqual(decoded?.isEmpty, true)
    }

    func testDuplicateCarriersCollapseToNewest() {
        let old = record([mark(1)], at: Date(timeIntervalSince1970: 1_000))
        let new = record([mark(2)], at: Date(timeIntervalSince1970: 2_000))
        _ = reconcile(local: [], stamp: .distantPast, records: [old, new])
        XCTAssertTrue(deleted.contains(where: { $0 === old }))
        XCTAssertFalse(deleted.contains(where: { $0 === new }))
    }

    func testOtherBooksRecordsAreUntouched() {
        let other = record([mark(1)], at: Date(timeIntervalSince1970: 5_000), book: UUID())
        XCTAssertEqual(reconcile(local: [], stamp: .distantPast, records: [other]), .noop)
        XCTAssertTrue(deleted.isEmpty)
    }

    // MARK: - store stamp semantics

    private func freshStore() -> BookmarkStore {
        BookmarkStore(directory: FileManager.default.temporaryDirectory
            .appendingPathComponent("bm-sync-tests-\(UUID().uuidString)", isDirectory: true))
    }

    func testAddStampsTheClock() {
        let store = freshStore()
        XCTAssertEqual(store.modifiedAt(bookID: bookID), .distantPast)
        store.add(mark(10), bookID: bookID)
        XCTAssertNotEqual(store.modifiedAt(bookID: bookID), .distantPast)
    }

    func testDedupedAddDoesNotStamp() {
        let store = freshStore()
        store.add(mark(10), bookID: bookID)
        let stamp = store.modifiedAt(bookID: bookID)
        store.add(mark(10.5), bookID: bookID)   // inside dedupeWindow → no change
        XCTAssertEqual(store.modifiedAt(bookID: bookID), stamp)
    }

    func testRemoveMissingDoesNotStamp() {
        let store = freshStore()
        store.add(mark(10), bookID: bookID)
        let stamp = store.modifiedAt(bookID: bookID)
        store.remove(id: UUID(), bookID: bookID)   // not in the list
        XCTAssertEqual(store.modifiedAt(bookID: bookID), stamp)
    }

    func testAdoptSyncedCopiesStampVerbatim() {
        let store = freshStore()
        let ts = Date(timeIntervalSince1970: 7_777)
        store.adoptSynced([mark(3), mark(30)], stamp: ts, bookID: bookID)
        XCTAssertEqual(store.load(bookID: bookID).count, 2)
        XCTAssertEqual(store.modifiedAt(bookID: bookID).timeIntervalSince1970,
                       ts.timeIntervalSince1970, accuracy: 0.001)
    }
}
