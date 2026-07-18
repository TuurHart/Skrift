import XCTest
@testable import SkriftMobile

/// The Fading lifecycle rulebook (Shared/Pipeline/MemoLifecycle) — design locked
/// 2026-07-17. Same file in both suites (desktop compiles Shared/ directly).
final class MemoLifecycleTests: XCTestCase {

    private let now = Date()
    private func daysAgo(_ n: Int) -> Date { now.addingTimeInterval(-Double(n) * 86_400) }

    /// A bare, untouched voice note recorded `days` ago.
    private func bareMemo(days: Int) -> Memo {
        Memo(audioFilename: "m.m4a", recordedAt: daysAgo(days),
             transcript: "just words", transcriptStatus: .done)
    }

    // MARK: fading / sweep timing

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
        XCTAssertTrue(MemoLifecycle.isFading(m, backlinked: [], now: now), "still shows on the shelf")
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

    // MARK: the touch-list (each signal alone prevents fading)

    func testEachTouchSignalPreventsFading() {
        let touches: [(String, (Memo) -> Void)] = [
            ("dots", { $0.significance = 0.1 }),
            ("edited", { $0.transcriptUserEdited = true }),
            ("title", { $0.title = "Named" }),
            ("tags", { $0.tags = ["idea"] }),
            ("locked", { $0.locked = true }),
            ("reminder", { $0.remindAt = self.now }),
            ("annotation", { $0.annotationText = "typed thought" }),
            ("kept", { $0.keptAt = self.now }),
        ]
        for (name, apply) in touches {
            let m = bareMemo(days: 90)
            apply(m)
            XCTAssertFalse(MemoLifecycle.isFading(m, backlinked: [], now: now), "\(name) must prevent fading")
        }
    }

    func testBlankTitleAndWhitespaceAnnotationAreNotTouches() {
        let m = bareMemo(days: 90)
        m.title = "  "
        m.annotationText = " \n"
        XCTAssertTrue(MemoLifecycle.isFading(m, backlinked: [], now: now))
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
}
