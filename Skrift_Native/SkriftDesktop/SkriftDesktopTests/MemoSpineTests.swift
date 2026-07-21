import XCTest

/// The spine (Shared/Pipeline/MemoSpine) — direction locked 2026-07-20
/// (mocks/lifecycle-ia-explorations.html). One status per note, first match
/// wins; the copy trio is SIGNED and pinned verbatim here. Same file in both
/// suites (mobile adds the @testable import).
final class MemoSpineTests: XCTestCase {

    private let now = Date()
    private func daysAgo(_ n: Int) -> Date { now.addingTimeInterval(-Double(n) * 86_400) }

    private func input(days: Int, deletedDaysAgo: Int? = nil, rated: Bool = false,
                       touch: MemoSpine.TouchReason? = nil, transcriptDone: Bool = true,
                       queue: MemoSpine.QueuePhase? = nil, macLocal: Bool = false) -> MemoSpine.Input {
        MemoSpine.Input(recordedAt: daysAgo(days),
                        deletedAt: deletedDaysAgo.map { daysAgo($0) },
                        rated: rated, touchReason: touch, transcriptDone: transcriptDone,
                        queue: queue, macLocalFile: macLocal)
    }

    // MARK: the chain — first match wins, one label per note

    func testDeletedBeatsEverything() {
        let st = MemoSpine.station(for: input(days: 100, deletedDaysAgo: 5, rated: true,
                                              touch: .tagged, queue: .exported), now: now)
        XCTAssertEqual(st, .deleted(goneAt: daysAgo(5).addingTimeInterval(TrashPolicy.retention)))
        XCTAssertEqual(MemoSpine.oneLiner(for: st, now: now), "gone for good in ~9d")
    }

    func testRatedWithoutQueueRowCountsAsToProcess() {
        // "a rated note whose queue row hasn't reconciled yet counts as To process"
        let st = MemoSpine.station(for: input(days: 1, rated: true), now: now)
        XCTAssertEqual(st, .toProcess)
        XCTAssertEqual(MemoSpine.oneLiner(for: st, now: now), "processes on next run")
    }

    func testActiveTrackFollowsTheQueuePhase() {
        XCTAssertEqual(MemoSpine.station(for: input(days: 1, rated: true, queue: .queued), now: now), .toProcess)
        XCTAssertEqual(MemoSpine.station(for: input(days: 1, rated: true, queue: .transcribing), now: now), .processing)
        XCTAssertEqual(MemoSpine.station(for: input(days: 1, rated: true, queue: .enhancing), now: now), .processing)
        XCTAssertEqual(MemoSpine.station(for: input(days: 1, rated: true, queue: .error), now: now), .stuck)
        XCTAssertEqual(MemoSpine.station(for: input(days: 1, rated: true, queue: .ready), now: now), .ready)
        XCTAssertEqual(MemoSpine.station(for: input(days: 1, rated: true, queue: .exported), now: now), .exported)
    }

    func testParkedNeverProcessesAndNeverFades() {
        // The zombie quadrant, named: touched-but-unrated stays parked at ANY age.
        let st = MemoSpine.station(for: input(days: 400, touch: .tagged), now: now)
        XCTAssertEqual(st, .parked(reason: .tagged))
        XCTAssertEqual(MemoSpine.oneLiner(for: st, now: now), "kept — tagged",
                       "no countdown ever on the siding")
    }

    func testLifecycleTrackNewThenFading() {
        let fresh = MemoSpine.station(for: input(days: 10), now: now)
        XCTAssertEqual(fresh, .new(fadesAt: daysAgo(10).addingTimeInterval(30 * 86_400)))
        let faded = MemoSpine.station(for: input(days: 31), now: now)
        XCTAssertEqual(faded, .fading(deletedAt: daysAgo(31).addingTimeInterval(60 * 86_400)))
    }

    func testStillTranscribingIsNewNeverFading() {
        // "A phone note still transcribing is New (the river's slim row)."
        let st = MemoSpine.station(for: input(days: 40, transcriptDone: false), now: now)
        if case .new = st {} else { XCTFail("transcribing note must stay New, got \(st)") }
    }

    func testMacLocalFileRidesTheActiveTrackAndNeverFades() {
        XCTAssertEqual(MemoSpine.station(for: input(days: 200, queue: .ready, macLocal: true), now: now), .ready)
        // …but a deleted Mac-local file still lands in Recently Deleted.
        let st = MemoSpine.station(for: input(days: 200, deletedDaysAgo: 2, queue: .ready, macLocal: true), now: now)
        if case .deleted = st {} else { XCTFail("deleted Mac-local file must be Deleted, got \(st)") }
    }

    // MARK: the signed copy trio (Q7) — verbatim, every surface reuses these

    func testCopyTrioPinnedVerbatim() {
        let newLine = MemoSpine.oneLiner(for: MemoSpine.station(for: input(days: 10), now: now), now: now)
        XCTAssertTrue(newLine.hasPrefix("starts fading "), "got: \(newLine)")

        XCTAssertEqual(MemoSpine.oneLiner(for: .fading(deletedAt: now.addingTimeInterval(6 * 86_400)), now: now),
                       "moves to Recently Deleted in 6d")
        XCTAssertEqual(MemoSpine.oneLiner(for: .fading(deletedAt: now), now: now),
                       "moves to Recently Deleted today")
        XCTAssertEqual(MemoSpine.oneLiner(for: .deleted(goneAt: now.addingTimeInterval(9 * 86_400)), now: now),
                       "gone for good in ~9d")
        XCTAssertEqual(MemoSpine.oneLiner(for: .deleted(goneAt: now), now: now), "gone for good soon")
    }

    func testStationNames() {
        XCTAssertEqual(MemoSpine.name(for: .deleted(goneAt: now)), "Recently Deleted")
        XCTAssertEqual(MemoSpine.name(for: .exported), "In Obsidian")
        XCTAssertEqual(MemoSpine.name(for: .parked(reason: .locked)), "Parked")
    }

    // MARK: the Memo builder + touch-reason order

    func testBuilderDerivesParkedFromATaggedUnratedMemo() {
        let memo = Memo(audioFilename: "m.m4a", recordedAt: daysAgo(3),
                        transcript: "just words", transcriptStatus: .done)
        memo.tags = ["garden"]
        let st = MemoSpine.station(for: .from(memo, backlinked: []), now: now)
        XCTAssertEqual(st, .parked(reason: .tagged))
    }

    func testTouchReasonFollowsIsTouchedOrder() {
        let memo = Memo(audioFilename: "m.m4a", recordedAt: daysAgo(3),
                        transcript: "just words", transcriptStatus: .done)
        memo.tags = ["garden"]
        memo.locked = true
        memo.transcriptUserEdited = true
        // edited outranks tagged outranks locked (MemoLifecycle.isTouched order).
        XCTAssertEqual(MemoSpine.touchReason(of: memo, backlinked: []), .edited)
    }

    func testRatingBeatsParking() {
        // Rated + tagged = active track, not the siding (rating is THE track switch).
        let memo = Memo(audioFilename: "m.m4a", recordedAt: daysAgo(3),
                        transcript: "just words", transcriptStatus: .done)
        memo.tags = ["garden"]
        memo.significance = 0.1
        XCTAssertEqual(MemoSpine.station(for: .from(memo, backlinked: []), now: now), .toProcess)
    }
}
