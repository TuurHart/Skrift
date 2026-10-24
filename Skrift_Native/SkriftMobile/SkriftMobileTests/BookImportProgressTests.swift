import XCTest
@testable import SkriftMobile

/// Q494 (C290): a long book-text import shows real progress (steps done of a known total) and
/// says listening can continue. The toast in the Text sheet draws `BookTextProgress`; these
/// tests pin the numbers it is fed.
final class BookImportProgressTests: XCTestCase {

    func testStepTotalCountsCopyParseEachFileAndChapters() {
        XCTAssertEqual(BookTextProgress.total(files: 12, copying: true), 15)
        XCTAssertEqual(BookTextProgress.total(files: 1, copying: true), 4)
        XCTAssertEqual(BookTextProgress.total(files: 3, copying: false), 5)
    }

    func testFractionAndCountLine() {
        let p = BookTextProgress(stage: "Matching the text… (file 3 of 12)", done: 4, total: 15)
        XCTAssertEqual(p.fraction, 4.0 / 15.0, accuracy: 1e-9)
        XCTAssertEqual(p.countLine, "4 of 15 done")
        XCTAssertEqual(p.tileLine, "Matching the text… (file 3 of 12) · 4 of 15 done")
    }

    func testUnknownTotalShowsNoBarOrCount() {
        let p = BookTextProgress(stage: "Checking the text against this audiobook…", done: 0, total: 0)
        XCTAssertEqual(p.fraction, 0)
        XCTAssertNil(p.countLine)
        XCTAssertEqual(p.tileLine, p.stage)
    }

    func testOverrunNeverExceedsFull() {
        let p = BookTextProgress(stage: "x", done: 9, total: 5)
        XCTAssertEqual(p.fraction, 1)
        XCTAssertEqual(p.countLine, "5 of 5 done")
    }

    func testListeningLineSaysPlaybackContinues() {
        XCTAssertEqual(BookTextProgress.listeningLine, "You can keep listening while this runs.")
    }

    @MainActor
    func testActivityPublishesProgressForTheLibraryAndSheet() {
        let activity = BookTextActivity()
        let id = UUID()
        activity.begin(id, stage: "Matching up your book text…")
        XCTAssertEqual(activity.stage, "Matching up your book text…")
        XCTAssertNil(activity.progress?.countLine)
        activity.update(BookTextProgress(stage: "Reading the text…", done: 2, total: 7))
        XCTAssertEqual(activity.progress?.countLine, "2 of 7 done")
        activity.end()
        XCTAssertNil(activity.progress)
        XCTAssertFalse(activity.isActive(id))
    }

    /// The real attach run on a two-file book: every report carries the same total, the count
    /// never goes backwards, and the run ends at total of total.
    func testAttachReportsMonotonicStepsEndingAtTotal() async throws {
        let book = Audiobook(files: ["part1.m4a", "part2.m4a"], fileDurations: [3600, 3600],
                             title: "Progress Fixture", author: "Nobody", duration: 7200)
        await MainActor.run { AudiobookLibraryStore.shared.add(book) }
        let txt = FileManager.default.temporaryDirectory.appendingPathComponent("progress_\(UUID().uuidString).txt")
        try "It was a long book, and it took a long time to read.".write(to: txt, atomically: true, encoding: .utf8)
        addTeardownBlock {
            try? FileManager.default.removeItem(at: txt)
            await MainActor.run {
                if let b = AudiobookLibraryStore.shared.book(id: book.id) { AudiobookLibraryStore.shared.remove(b) }
            }
        }

        final class Log: @unchecked Sendable {
            private let lock = NSLock()
            private var items: [BookTextProgress] = []
            func add(_ p: BookTextProgress) { lock.lock(); items.append(p); lock.unlock() }
            var all: [BookTextProgress] { lock.lock(); defer { lock.unlock() }; return items }
        }
        let log = Log()
        _ = try await BookAlignmentRunner.attach(bookFileAt: txt, bookID: book.id) { log.add($0) }

        let events = log.all
        XCTAssertFalse(events.isEmpty)
        let total = BookTextProgress.total(files: 2, copying: true)
        XCTAssertEqual(Set(events.map(\.total)), [total], "one known total for the whole run")
        XCTAssertEqual(events.map(\.done), events.map(\.done).sorted(), "the count never goes backwards")
        XCTAssertEqual(events.first?.done, 0)
        XCTAssertEqual(events.last?.done, total)
        XCTAssertTrue(events.contains { $0.stage == "Placing chapters…" && $0.done == total - 1 })
    }
}
