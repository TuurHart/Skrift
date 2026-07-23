import XCTest
@testable import SkriftMobile

/// The spine (Shared/Pipeline/MemoSpine) — v2 "one clock", signed 2026-07-22
/// (mocks/lifecycle-triage-peek.html #m5/#m6; v1 locked 2026-07-20). One status
/// per note, first match wins; the copy trio is SIGNED and pinned verbatim
/// here. Same file in both suites (mobile adds the @testable import).
final class MemoSpineTests: XCTestCase {

    private let now = Date()
    private func daysAgo(_ n: Int) -> Date { now.addingTimeInterval(-Double(n) * 86_400) }

    private func input(days: Int, keptDaysAgo: Int? = nil, deletedDaysAgo: Int? = nil,
                       seenDaysAgo: Int? = nil,
                       rated: Bool = false, hold: MemoSpine.HoldReason? = nil,
                       transcriptDone: Bool = true, queue: MemoSpine.QueuePhase? = nil,
                       macLocal: Bool = false) -> MemoSpine.Input {
        MemoSpine.Input(recordedAt: daysAgo(days),
                        keptAt: keptDaysAgo.map { daysAgo($0) },
                        deletedAt: deletedDaysAgo.map { daysAgo($0) },
                        trashSeenAt: seenDaysAgo.map { daysAgo($0) },
                        rated: rated, holdReason: hold, transcriptDone: transcriptDone,
                        queue: queue, macLocalFile: macLocal)
    }

    // MARK: the chain — first match wins, one label per note

    func testDeletedBeatsEverything() {
        let st = MemoSpine.station(for: input(days: 100, deletedDaysAgo: 5, seenDaysAgo: 5, rated: true,
                                              hold: .locked, queue: .exported), now: now)
        XCTAssertEqual(st, .deleted(goneAt: daysAgo(5).addingTimeInterval(TrashPolicy.retention)))
        XCTAssertEqual(MemoSpine.oneLiner(for: st, now: now), "gone for good in ~9d")
    }

    func testUnseenDeletionCountsFromNowNotFromDeletedAt() {
        // v3 (2026-07-23): a deletion that synced in while the app sat closed
        // has NO purge clock yet — the label shows the full window from `now`,
        // matching the purge gate, so the shown date stays true. A stale
        // sighting (before the current stay) counts the same as none.
        for st in [MemoSpine.station(for: input(days: 100, deletedDaysAgo: 30), now: now),
                   MemoSpine.station(for: input(days: 100, deletedDaysAgo: 30, seenDaysAgo: 45), now: now)] {
            XCTAssertEqual(st, .deleted(goneAt: now.addingTimeInterval(TrashPolicy.retention)))
            XCTAssertEqual(MemoSpine.oneLiner(for: st, now: now), "gone for good in ~14d")
        }
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

    func testTouchRestartsTheClockInsteadOfParking() {
        // One clock (kills the Parked siding): a touched-but-unrated note is
        // just a clock-run note with a fresher anchor — 30 fresh days, then it
        // fades like everything else.
        let fresh = MemoSpine.station(for: input(days: 400, keptDaysAgo: 5), now: now)
        XCTAssertEqual(fresh, .new(fadesAt: daysAgo(5).addingTimeInterval(30 * 86_400)))

        let stale = MemoSpine.station(for: input(days: 400, keptDaysAgo: 40), now: now)
        XCTAssertEqual(stale, .fading(deletedAt: daysAgo(40).addingTimeInterval(60 * 86_400)),
                       "a 40-day-old touch has run out — no immortality")
    }

    func testHeldNotesSitOffTheClockAtAnyAge() {
        for (reason, line) in [(MemoSpine.HoldReason.locked, "locked — won't fade"),
                               (.reminder, "reminder set — won't fade"),
                               (.linked, "linked — won't fade")] {
            let st = MemoSpine.station(for: input(days: 400, hold: reason), now: now)
            XCTAssertEqual(st, .held(reason: reason))
            XCTAssertEqual(MemoSpine.oneLiner(for: st, now: now), line)
        }
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
        XCTAssertEqual(MemoSpine.name(for: .held(reason: .locked)), "Held")
    }

    // MARK: the peek chip + sentence (m6)

    func testChipTextCompactsOnlyTheQuietLeg() {
        let chip = MemoSpine.chipText(for: MemoSpine.station(for: input(days: 10), now: now), now: now)
        XCTAssertTrue(chip.hasPrefix("fades "), "got: \(chip)")
        // Every other station's chip IS its one-liner.
        let fading = MemoSpine.Station.fading(deletedAt: now.addingTimeInterval(6 * 86_400))
        XCTAssertEqual(MemoSpine.chipText(for: fading, now: now), MemoSpine.oneLiner(for: fading, now: now))
    }

    func testPeekSentenceHoldsBothTruths() {
        // Touched: names the touch, the restarted clock, and the gate.
        let touched = Memo(audioFilename: "m.m4a", recordedAt: daysAgo(30),
                           transcript: "just words", transcriptStatus: .done)
        touched.transcriptUserEdited = true
        touched.keptAt = daysAgo(2)
        let s1 = MemoSpine.peekSentence(for: touched, backlinked: [], now: now)
        XCTAssertTrue(s1.hasPrefix("You edited this on "), "got: \(s1)")
        XCTAssertTrue(s1.contains("which restarted its clock"), "got: \(s1)")
        XCTAssertTrue(s1.contains("unless you rate it"), "got: \(s1)")

        // Untouched: the gate + the clock, nothing about touches.
        let bare = Memo(audioFilename: "m.m4a", recordedAt: daysAgo(3),
                        transcript: "just words", transcriptStatus: .done)
        let s2 = MemoSpine.peekSentence(for: bare, backlinked: [], now: now)
        XCTAssertTrue(s2.hasPrefix("Not rated, so the Mac won't polish it"), "got: \(s2)")

        // Held: the why + the gate.
        let locked = Memo(audioFilename: "m.m4a", recordedAt: daysAgo(3),
                          transcript: "just words", transcriptStatus: .done)
        locked.locked = true
        let s3 = MemoSpine.peekSentence(for: locked, backlinked: [], now: now)
        XCTAssertTrue(s3.hasPrefix("Locked, so it never fades"), "got: \(s3)")
    }

    // MARK: the Memo builder + hold-reason order

    func testBuilderPutsLegacyTaggedMemoOnTheClock() {
        // Pre-migration reality, documented: tags no longer hold — an old
        // tagged memo with no keptAt is FADING until the one-clock migration
        // gives it a fresh anchor.
        let memo = Memo(audioFilename: "m.m4a", recordedAt: daysAgo(40),
                        transcript: "just words", transcriptStatus: .done)
        memo.tags = ["garden"]
        if case .fading = MemoSpine.station(for: .from(memo, backlinked: []), now: now) {} else {
            XCTFail("legacy tagged memo must be on the clock")
        }
        MemoLifecycle.migrateParkedToOneClock([memo], now: now)
        XCTAssertEqual(MemoSpine.station(for: .from(memo, backlinked: []), now: now),
                       .new(fadesAt: now.addingTimeInterval(30 * 86_400)))
    }

    func testHoldReasonOrderAndRatingBeatsEverything() {
        let memo = Memo(audioFilename: "m.m4a", recordedAt: daysAgo(3),
                        transcript: "just words", transcriptStatus: .done)
        memo.locked = true
        memo.remindAt = now
        // locked outranks reminder (neverFades order, minus rating).
        XCTAssertEqual(MemoSpine.holdReason(of: memo, backlinked: []), .locked)
        // Rated + locked = active track, not held (rating is THE track switch).
        memo.significance = 0.1
        XCTAssertEqual(MemoSpine.station(for: .from(memo, backlinked: []), now: now), .toProcess)
    }
}
