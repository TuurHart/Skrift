import XCTest
@testable import SkriftMobile

/// Wave-2 text-capture: the per-book transcript sidecar (model math + store I/O).
final class BookTranscriptTests: XCTestCase {

    private func words(_ pairs: [(String, Double, Double)]) -> [WordTiming] {
        pairs.map { WordTiming(word: $0.0, start: $0.1, end: $0.2) }
    }

    // MARK: - FileTranscript pure math

    func testIsCoveredUpToFrontierWithEpsilon() {
        let ft = FileTranscript(fileIndex: 0, signature: "s", coveredUpTo: 120)
        XCTAssertTrue(ft.isCovered(upTo: 0))
        XCTAssertTrue(ft.isCovered(upTo: 120))
        XCTAssertTrue(ft.isCovered(upTo: 120.04))   // within epsilon (chunk-boundary drift)
        XCTAssertFalse(ft.isCovered(upTo: 121))
    }

    func testWordsInWindowReturnsOverlapping() {
        let ft = FileTranscript(fileIndex: 0, signature: "s", coveredUpTo: 10,
                                words: words([("a", 0, 1), ("b", 2, 3), ("c", 5, 6), ("d", 8, 9)]))
        // Window [2.5, 6] overlaps "b" (2-3), "c" (5-6).
        XCTAssertEqual(ft.words(inWindow: 2.5, end: 6).map(\.word), ["b", "c"])
        // Degenerate window → empty.
        XCTAssertEqual(ft.words(inWindow: 5, end: 5).map(\.word), [])
    }

    func testAppendingAdvancesFrontierAndAppendsWords() {
        let ft = FileTranscript(fileIndex: 0, signature: "s", coveredUpTo: 3,
                                words: words([("a", 0, 1), ("b", 2, 3)]))
        let next = ft.appending(words([("c", 3, 4), ("d", 4, 5)]), upTo: 5)
        XCTAssertEqual(next.coveredUpTo, 5)
        XCTAssertEqual(next.words.map(\.word), ["a", "b", "c", "d"])
    }

    func testAppendingIgnoresStaleChunk() {
        // A torn / re-run chunk that ends at or behind the saved frontier is a
        // no-op — the resume contract: never corrupt the saved transcript.
        let ft = FileTranscript(fileIndex: 0, signature: "s", coveredUpTo: 5,
                                words: words([("a", 0, 1)]))
        let same = ft.appending(words([("x", 4, 5)]), upTo: 5)
        XCTAssertEqual(same, ft)
        let behind = ft.appending(words([("x", 4, 4.5)]), upTo: 4.5)
        XCTAssertEqual(behind, ft)
    }

    // MARK: - Store I/O (temp dir)

    private func tempStore() -> BookTranscriptStore {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("bt_\(UUID().uuidString)", isDirectory: true)
        return BookTranscriptStore(directory: dir)
    }

    func testSaveLoadRoundTrip() throws {
        let store = tempStore()
        let id = UUID()
        let ft = FileTranscript(fileIndex: 2, signature: "100:200", coveredUpTo: 7,
                                words: words([("hello", 0, 1), ("world", 1, 2)]))
        try store.save(ft, bookID: id)
        let back = store.load(bookID: id, fileIndex: 2, expectedSignature: "100:200")
        XCTAssertEqual(back, ft)
    }

    func testLoadNilOnStaleSignature() throws {
        let store = tempStore()
        let id = UUID()
        try store.save(FileTranscript(fileIndex: 0, signature: "100:200", coveredUpTo: 7), bookID: id)
        // Re-imported file → different signature → treated as un-transcribed.
        XCTAssertNil(store.load(bookID: id, fileIndex: 0, expectedSignature: "999:999"))
        // Matching signature still loads.
        XCTAssertNotNil(store.load(bookID: id, fileIndex: 0, expectedSignature: "100:200"))
    }

    func testLoadNilWhenMissing() {
        let store = tempStore()
        XCTAssertNil(store.load(bookID: UUID(), fileIndex: 0, expectedSignature: "x"))
    }

    func testRemoveTranscriptsSweepsSidecars() throws {
        let store = tempStore()
        let id = UUID()
        try store.save(FileTranscript(fileIndex: 0, signature: "a", coveredUpTo: 1), bookID: id)
        try store.save(FileTranscript(fileIndex: 1, signature: "b", coveredUpTo: 1), bookID: id)
        store.removeTranscripts(forBookID: id)
        XCTAssertNil(store.load(bookID: id, fileIndex: 0, expectedSignature: "a"))
        XCTAssertNil(store.load(bookID: id, fileIndex: 1, expectedSignature: "b"))
    }
}
