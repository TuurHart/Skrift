import XCTest
@testable import SkriftMobile

/// The lifecycle rulebook (Shared/Pipeline/MemoLifecycle) — v2 "one clock",
/// signed 2026-07-22 (supersedes the 2026-07-17 "touched never fades"). Same
/// file in both suites (desktop compiles Shared/ directly).
final class MemoLifecycleTests: XCTestCase {

    private let now = Date()
    private func daysAgo(_ n: Int) -> Date { now.addingTimeInterval(-Double(n) * 86_400) }

    /// A bare voice note recorded `days` ago — clock running from recording.
    private func bareMemo(days: Int) -> Memo {
        Memo(audioFilename: "m.m4a", recordedAt: daysAgo(days),
             transcript: "just words", transcriptStatus: .done)
    }

    // MARK: fading / sweep timing (anchor = recordedAt when never touched)

    func testFreshUntouchedNoteIsNotFading() {
        XCTAssertFalse(MemoLifecycle.isFading(bareMemo(days: 29), backlinked: [], now: now))
    }

    func testUntouchedNoteFadesAt30Days() {
        let m = bareMemo(days: 31)
        XCTAssertTrue(MemoLifecycle.isFading(m, backlinked: [], now: now))
        XCTAssertFalse(MemoLifecycle.sweepDue(m, backlinked: [], now: now), "fading ≠ sweep-due yet")
    }

    func testSweepDueAt60Days() {
        let m = bareMemo(days: 61)
        XCTAssertTrue(MemoLifecycle.isFading(m, backlinked: [], now: now), "still shows on the conveyor")
        XCTAssertTrue(MemoLifecycle.sweepDue(m, backlinked: [], now: now))
        XCTAssertEqual(MemoLifecycle.daysUntilSweep(m, now: now), 0, "\"fades today\"")
    }

    func testCountdownDays() {
        XCTAssertEqual(MemoLifecycle.daysUntilSweep(bareMemo(days: 56), now: now), 4)
    }

    func testFadeEntersAtIsThe30DayLine() {
        let m = bareMemo(days: 0)
        XCTAssertEqual(MemoLifecycle.fadeEntersAt(m).timeIntervalSince(m.recordedAt),
                       30 * 86_400, accuracy: 1)
    }

    // MARK: the one clock — touches restart it, nothing more

    func testTouchRestartsTheFadeClock() {
        let m = bareMemo(days: 90)
        MemoLifecycle.touch(m, now: daysAgo(3))
        XCTAssertFalse(MemoLifecycle.isFading(m, backlinked: [], now: now), "3-day-old touch = fresh clock")
        XCTAssertEqual(MemoLifecycle.fadesAt(m), daysAgo(3).addingTimeInterval(60 * 86_400))
        XCTAssertEqual(MemoLifecycle.daysUntilSweep(m, now: now), 57)

        let stale = bareMemo(days: 90)
        MemoLifecycle.touch(stale, now: daysAgo(31))
        XCTAssertTrue(MemoLifecycle.isFading(stale, backlinked: [], now: now),
                      "a 31-day-old touch has run out — no immortality")
    }

    func testEditsTitlesTagsAnnotationsNoLongerHold() {
        // v1 immortality flags are display signals now; the compat path is the
        // one-clock migration (below), not the predicate.
        let signals: [(String, (Memo) -> Void)] = [
            ("edited", { $0.transcriptUserEdited = true }),
            ("title", { $0.title = "Named" }),
            ("tags", { $0.tags = ["idea"] }),
            ("annotation", { $0.annotationText = "typed thought" }),
        ]
        for (name, apply) in signals {
            let m = bareMemo(days: 90)
            apply(m)
            XCTAssertTrue(MemoLifecycle.isFading(m, backlinked: [], now: now),
                          "\(name) alone must NOT hold a note off the clock")
        }
    }

    func testHoldsAndRatingPreventFading() {
        let holds: [(String, (Memo) -> Void)] = [
            ("rated", { $0.significance = 0.1 }),
            ("locked", { $0.locked = true }),
            ("reminder", { $0.remindAt = self.now }),
            ("fresh keptAt", { $0.keptAt = self.now }),
        ]
        for (name, apply) in holds {
            let m = bareMemo(days: 90)
            apply(m)
            XCTAssertFalse(MemoLifecycle.isFading(m, backlinked: [], now: now), "\(name) must prevent fading")
        }
    }

    func testBacklinkedNoteNeverFades() {
        let m = bareMemo(days: 90)
        XCTAssertFalse(MemoLifecycle.isFading(m, backlinked: [m.id], now: now))
    }

    // MARK: guards

    func testInFlightAndTrashedNotesNeverFade() {
        let inflight = bareMemo(days: 90)
        inflight.transcriptStatus = .transcribing
        XCTAssertFalse(MemoLifecycle.isFading(inflight, backlinked: [], now: now))

        let trashed = bareMemo(days: 90)
        trashed.deletedAt = now
        XCTAssertFalse(MemoLifecycle.isFading(trashed, backlinked: [], now: now))
    }

    // MARK: v3 "no note dies unseen" (2026-07-23) — the trash clock

    func testTrashClockNeedsAValidSighting() {
        let unseen = bareMemo(days: 90)
        unseen.deletedAt = daysAgo(30)                       // synced in, never seen
        XCTAssertNil(MemoLifecycle.trashClockStart(unseen))
        XCTAssertFalse(MemoLifecycle.purgeDue(unseen, now: now),
                       "no sighting — a month in the trash burns nothing")
        XCTAssertEqual(MemoLifecycle.goneAt(unseen, now: now),
                       now.addingTimeInterval(TrashPolicy.retention),
                       "the label promises a full window from now — the truth")

        let stale = bareMemo(days: 90)
        stale.deletedAt = daysAgo(20)
        stale.trashSeenAt = daysAgo(40)                      // stamp from a PREVIOUS stay
        XCTAssertNil(MemoLifecycle.trashClockStart(stale), "restore → re-trash invalidates by construction")

        let seen = bareMemo(days: 90)
        seen.deletedAt = daysAgo(20)
        seen.trashSeenAt = daysAgo(15)                       // opened 5 days after it landed
        XCTAssertEqual(MemoLifecycle.trashClockStart(seen), daysAgo(15))
        XCTAssertTrue(MemoLifecycle.purgeDue(seen, now: now), "15 seen days ≥ the 14-day window")
        XCTAssertFalse(MemoLifecycle.purgeDue(seen, now: daysAgo(2)), "13 seen days — not yet")
    }

    func testStampTrashSightingsStartsOnlyMissingClocks() {
        let unseen = bareMemo(days: 90);  unseen.deletedAt = daysAgo(30)
        let seen = bareMemo(days: 90);    seen.deletedAt = daysAgo(10); seen.trashSeenAt = daysAgo(10)
        let live = bareMemo(days: 90)

        XCTAssertEqual(MemoLifecycle.stampTrashSightings([unseen, seen, live], now: now), 1)
        XCTAssertEqual(unseen.trashSeenAt, now, "clock starts at THIS open")
        XCTAssertEqual(seen.trashSeenAt, daysAgo(10), "a running clock is never restarted")
        XCTAssertNil(live.trashSeenAt, "not trashed — nothing to stamp")
        XCTAssertEqual(MemoLifecycle.stampTrashSightings([unseen, seen, live], now: now), 0, "idempotent")
    }

    // MARK: backlink scan + partition

    func testBacklinkScanAndPartition() {
        let old = bareMemo(days: 90)               // untouched + old → would fade…
        let linker = bareMemo(days: 1)
        linker.transcript = "see [[memo:\(old.id.uuidString)|Old thought]] again"
        let junk = bareMemo(days: 90)              // untouched + old + unlinked → fades

        let ids = MemoLifecycle.backlinkedIDs(in: [old, linker, junk])
        XCTAssertEqual(ids, [old.id], "…but the backlink keeps it")

        let split = MemoLifecycle.partition([old, linker, junk], now: now)
        XCTAssertEqual(Set(split.fading.map(\.id)), [junk.id])
        XCTAssertEqual(Set(split.live.map(\.id)), [old.id, linker.id])
    }

    // MARK: the one-clock migration (2026-07-22)

    func testMigrationGivesOldParkedNotesAFreshClock() {
        let edited = bareMemo(days: 90);    edited.transcriptUserEdited = true
        let titled = bareMemo(days: 90);    titled.title = "Named"
        let tagged = bareMemo(days: 90);    tagged.tags = ["idea"]
        let annotated = bareMemo(days: 90); annotated.annotationText = "typed thought"

        let blank = bareMemo(days: 90);     blank.title = "  "; blank.annotationText = " \n"
        let rated = bareMemo(days: 90);     rated.significance = 0.5; rated.transcriptUserEdited = true
        let kept = bareMemo(days: 90);      kept.transcriptUserEdited = true; kept.keptAt = daysAgo(10)
        let trashed = bareMemo(days: 90);   trashed.transcriptUserEdited = true; trashed.deletedAt = now
        let bare = bareMemo(days: 90)

        let all = [edited, titled, tagged, annotated, blank, rated, kept, trashed, bare]
        let bumped = MemoLifecycle.migrateParkedToOneClock(all, now: now)

        XCTAssertEqual(bumped, 4, "exactly the four old-doctrine parked notes")
        for m in [edited, titled, tagged, annotated] {
            XCTAssertEqual(m.keptAt, now, "parked note gets a fresh clock")
            XCTAssertFalse(MemoLifecycle.isFading(m, backlinked: [], now: now))
        }
        XCTAssertNil(blank.keptAt, "whitespace was never a touch")
        XCTAssertNil(rated.keptAt, "rated notes ride the active track")
        XCTAssertEqual(kept.keptAt, daysAgo(10), "an existing keptAt is never moved")
        XCTAssertNil(trashed.keptAt, "trash is left alone")
        XCTAssertNil(bare.keptAt)

        XCTAssertEqual(MemoLifecycle.migrateParkedToOneClock(all, now: now), 0, "idempotent")
    }
}
