import XCTest
@testable import SkriftMobile

/// Q474 (C267, D214): highlights from two devices merge per highlight id, never whole-list
/// last-writer-wins. Adds union, a removal is a stamped tombstone, a comment edit is LWW per
/// highlight. The pure rule (`SourceHighlights.merged`, Shared) plus the real sync path: two
/// library stores (phone, iPad) sharing one in-memory carrier repository.
@MainActor
final class HighlightMergeTests: XCTestCase {

    private var dir: URL!
    private var phone: AudiobookLibraryStore!, iPad: AudiobookLibraryStore!
    private var repo: NotesRepository!
    private var transport: InMemoryAudiobookTransport!
    private var suiteName: String!
    private var defaults: UserDefaults!
    /// Recent, so tombstones are inside the 90-day window the sync's real clock prunes by.
    private let base = Date().addingTimeInterval(-3600)

    override func setUpWithError() throws {
        dir = FileManager.default.temporaryDirectory.appendingPathComponent("q474_\(UUID().uuidString)", isDirectory: true)
        phone = AudiobookLibraryStore(directory: dir.appendingPathComponent("phone", isDirectory: true))
        iPad = AudiobookLibraryStore(directory: dir.appendingPathComponent("ipad", isDirectory: true))
        repo = NotesRepository(inMemory: true)
        transport = InMemoryAudiobookTransport()
        suiteName = "q474_\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: dir)
        defaults.removePersistentDomain(forName: suiteName)
    }

    private func at(_ s: TimeInterval) -> Date { base.addingTimeInterval(s) }

    private func sync(_ library: AudiobookLibraryStore) async {
        await AudiobookCloudSync.reconcile(library: library, repository: repo, defaults: defaults, transport: transport)
    }

    /// An article on the phone, synced to the iPad (no files, so only the record travels).
    private func sharedArticle() async -> UUID {
        var book = Audiobook(files: [], fileDurations: [], title: "Local-first software", author: "",
                             duration: 0, modifiedAt: at(0))
        book.kind = .article
        phone.add(book)
        AudiobookCloudSync.enableSync(book: book, repository: repo)
        await sync(phone)
        await sync(iPad)
        XCTAssertNotNil(iPad.book(id: book.id), "the article reached the iPad")
        return book.id
    }

    private func texts(_ id: UUID, _ library: AudiobookLibraryStore) -> [String] {
        LibraryHighlights.list(id, store: library).map(\.text)
    }

    // MARK: - The pure rule (Shared)

    func testPureMergeUnionsAddsAndIsCommutative() {
        let a = SourceHighlight(text: "one", page: 1, word: 0, createdAt: at(10))
        let b = SourceHighlight(text: "two", page: 2, word: 0, createdAt: at(20))
        let ab = SourceHighlights.merged([a], removals: [:], with: [b], removals: [:], now: at(30))
        let ba = SourceHighlights.merged([b], removals: [:], with: [a], removals: [:], now: at(30))
        XCTAssertEqual(ab.highlights.map(\.text), ["one", "two"])
        XCTAssertEqual(ab.highlights, ba.highlights, "every device reaches the same list in any sync order")
    }

    func testPureMergeRemovalBeatsAnOlderAddAndPrunesAfter90Days() {
        let h = SourceHighlight(text: "gone", page: 1, word: 0, createdAt: at(10))
        let removed = SourceHighlights.merged([], removals: [h.id.uuidString: at(20)], with: [h], removals: [:], now: at(30))
        XCTAssertTrue(removed.highlights.isEmpty, "the removal stamp beats the other device's older copy")
        XCTAssertEqual(removed.removals[h.id.uuidString], at(20), "the tombstone is kept")
        let later = at(20).addingTimeInterval(SourceHighlights.removalLifetime + 1)
        XCTAssertTrue(SourceHighlights.merged([], removals: removed.removals, with: [], removals: [:], now: later)
            .removals.isEmpty, "tombstones are pruned after 90 days")
    }

    func testPureMergeKeepsTheLaterCommentAndALaterClear() {
        let h = SourceHighlight(text: "budget", page: 2, word: 0, createdAt: at(10))
        let older = SourceHighlights.commenting(h.id, comment: "Ask Rui.", audio: nil, in: [h], now: at(20))
        let newer = SourceHighlights.commenting(h.id, comment: "Ask Rui about Sines.", audio: nil, in: [h], now: at(30))
        XCTAssertEqual(SourceHighlights.merged(older, removals: [:], with: newer, removals: [:]).highlights.first?.comment,
                       "Ask Rui about Sines.")
        XCTAssertEqual(SourceHighlights.merged(newer, removals: [:], with: older, removals: [:]).highlights.first?.comment,
                       "Ask Rui about Sines.")
        let cleared = SourceHighlights.commenting(h.id, comment: "", audio: nil, in: older, now: at(40))
        XCTAssertNil(SourceHighlights.merged(newer, removals: [:], with: cleared, removals: [:]).highlights.first?.comment,
                     "a later clear beats an earlier comment")
    }

    // MARK: - Through the real sync (phone + iPad)

    /// The item's first case: a highlight added offline on each device survives on both, whichever
    /// device reaches the carrier first.
    func testTwoOfflineAddsBothSurvive() async {
        let id = await sharedArticle()
        LibraryHighlights.add("on your own device first", page: nil, word: 20, bookID: id, store: phone, now: at(100))
        LibraryHighlights.add("the cloud is a backup", page: nil, word: 40, bookID: id, store: iPad, now: at(200))
        await sync(phone)   // phone reaches the carrier first with the OLDER edit
        await sync(iPad)    // iPad's newer blob would have overwritten the phone's highlight
        await sync(phone)
        XCTAssertEqual(texts(id, phone), ["on your own device first", "the cloud is a backup"])
        XCTAssertEqual(texts(id, iPad), ["on your own device first", "the cloud is a backup"])
    }

    /// The item's second case: removing a highlight on one device beats the other device's older copy.
    func testARemoveOnOneDeviceBeatsAnOlderAdd() async throws {
        let id = await sharedArticle()
        let hid = LibraryHighlights.add("on your own device first", page: nil, word: 20, bookID: id, store: phone, now: at(100))
        await sync(phone)
        await sync(iPad)
        XCTAssertEqual(texts(id, iPad), ["on your own device first"])
        // Offline: the iPad removes it; the phone, later, adds another one (its blob is the newer).
        LibraryHighlights.remove(try XCTUnwrap(hid), bookID: id, store: iPad, now: at(200))
        LibraryHighlights.add("the cloud is a backup", page: nil, word: 40, bookID: id, store: phone, now: at(300))
        await sync(iPad)
        await sync(phone)
        await sync(iPad)
        XCTAssertEqual(texts(id, phone), ["the cloud is a backup"], "the iPad's removal reached the phone")
        XCTAssertEqual(texts(id, iPad), ["the cloud is a backup"], "the phone's add reached the iPad, the removed one stayed gone")
    }

    /// The item's third case: a comment edited on both devices keeps the later edit on both.
    func testCommentEditsAreLastWriterWinsPerHighlight() async throws {
        let id = await sharedArticle()
        let hid = try XCTUnwrap(LibraryHighlights.add("budget line", page: nil, word: 5, bookID: id, store: phone, now: at(100)))
        let other = try XCTUnwrap(LibraryHighlights.add("travel", page: nil, word: 9, bookID: id, store: phone, now: at(110)))
        await sync(phone)
        await sync(iPad)
        // Offline: the iPad comments on `hid` later; the phone comments on it earlier and on `other`.
        LibraryHighlights.setComment("Ask Rui.", audio: nil, on: hid, bookID: id, store: phone, now: at(200))
        LibraryHighlights.setComment("Flights only.", audio: nil, on: other, bookID: id, store: phone, now: at(210))
        LibraryHighlights.setComment("Ask Rui about Sines.", audio: nil, on: hid, bookID: id, store: iPad, now: at(300))
        await sync(iPad)
        await sync(phone)
        await sync(iPad)
        for library in [phone!, iPad!] {
            XCTAssertEqual(LibraryHighlights.highlight(hid, bookID: id, store: library)?.comment, "Ask Rui about Sines.")
            XCTAssertEqual(LibraryHighlights.highlight(other, bookID: id, store: library)?.comment, "Flights only.",
                           "the phone's comment on the other highlight survives the iPad's newer blob")
        }
    }

    /// A blob a pre-Q474 build wrote has no tombstone key: that adopt keeps today's whole-blob LWW.
    func testABlobWithoutStampsFallsBackToLastWriterWins() throws {
        var local = Audiobook(files: [], fileDurations: [], title: "T", author: "", duration: 0)
        local.highlights = [SourceHighlight(text: "mine", page: nil, word: 0)]
        var remote = local
        remote.highlights = [SourceHighlight(text: "theirs", page: nil, word: 0)]
        var json = try JSONSerialization.jsonObject(with: JSONEncoder().encode(remote)) as! [String: Any]
        json.removeValue(forKey: "highlightRemovals")
        let old = try JSONDecoder().decode(Audiobook.self, from: JSONSerialization.data(withJSONObject: json))
        XCTAssertNil(AudiobookCloudSync.mergedHighlights(local: local, remote: old))
        let synced = try JSONDecoder().decode(Audiobook.self, from: JSONEncoder().encode(remote.sanitizedForSync()))
        XCTAssertNotNil(synced.highlightRemovals, "a new build's blob always carries the key")
        XCTAssertEqual(AudiobookCloudSync.mergedHighlights(local: local, remote: synced)?.highlights.count, 2)
    }
}
