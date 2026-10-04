import XCTest
@testable import SkriftMobile

/// Q282 (D167, C115): the phone and iPad Notes list ask the ONE shared `QueueFilter.admits`
/// (the Mac sidebar asks the same through `MacListFilter`). Done = processed on any device;
/// exporting is never part of it. Driven through the list's own static filter path.
@MainActor
final class QueueFilterPhoneTests: XCTestCase {

    private func memo(rated: Bool, locked: Bool = false) -> Memo {
        let m = Memo(audioFilename: "x.m4a", transcript: "some words", transcriptStatus: .done,
                     significance: rated ? 0.5 : 0)
        m.locked = locked
        return m
    }

    private func chips(_ m: Memo, enhanced: Set<UUID>) -> Set<QueueFilter> {
        Set(QueueFilter.allCases.filter {
            MemosListView.passesFilter(m, chip: $0, filter: MemoFilter(), enhanced: enhanced)
        })
    }

    func testProcessedNoteIsDone() {
        let m = memo(rated: true)
        XCTAssertEqual(chips(m, enhanced: [m.id]), [.all, .done],
                       "D167: processed (on any device) is Done, exported or not")
    }

    func testUnprocessedRatedNoteNeedsWork() {
        XCTAssertEqual(chips(memo(rated: true), enhanced: []), [.all, .needsWork])
    }

    func testLockedProcessedNoteIsStillDone() {
        let m = memo(rated: true, locked: true)
        XCTAssertEqual(chips(m, enhanced: [m.id]), [.all, .done])
    }

    func testUnratedNotes() {
        XCTAssertEqual(chips(memo(rated: false), enhanced: []), [.all, .notRated])
        XCTAssertEqual(chips(memo(rated: false, locked: true), enhanced: []), [.all])
    }

    /// The list path and the shared predicate never disagree, for any chip or memo kind.
    func testListPathIsTheSharedPredicate() {
        let memos = [memo(rated: true), memo(rated: true), memo(rated: false),
                     memo(rated: false, locked: true), memo(rated: true, locked: true)]
        let enhanced: Set<UUID> = [memos[1].id, memos[4].id]
        for c in QueueFilter.allCases {
            for m in memos {
                XCTAssertEqual(MemosListView.passesFilter(m, chip: c, filter: MemoFilter(), enhanced: enhanced),
                               c.admits(rated: NoteConsent.isRated(m), processed: enhanced.contains(m.id),
                                        locked: m.locked), "\(c)")
            }
        }
    }
}
