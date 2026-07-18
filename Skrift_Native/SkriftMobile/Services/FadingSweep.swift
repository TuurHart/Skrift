import Foundation

/// The Fading lifecycle's timed half (design 2026-07-17, `MemoLifecycle`): move
/// sweep-due notes (untouched, 60+ days) into Recently Deleted — the EXISTING
/// soft-delete, so everything stays visible, restorable, and only the trash's
/// own 14-day countdown ever deletes for real.
///
/// Runs on launch, per device, idempotent (a note another device already swept
/// is simply no longer live here). Fully automatic (Tuur, 2026-07-18 device
/// round — the "Start the timers" arming gate read as friction, and the trash's
/// 14 reversible days + the shelf counts are the safety): doing nothing IS the
/// cleanup, from day one.
@MainActor
enum FadingSweep {

    /// Sweep everything due. Returns the count moved.
    @discardableResult
    static func run(repository: NotesRepository, now: Date = Date()) -> Int {
        let all = repository.allMemos()
        let backlinked = MemoLifecycle.backlinkedIDs(in: all)
        var swept = 0
        for memo in all where MemoLifecycle.sweepDue(memo, backlinked: backlinked, now: now) {
            repository.softDelete(memo, at: now)
            swept += 1
        }
        if swept > 0 { DevLog.log("FadingSweep: \(swept) note(s) → Recently Deleted") }
        return swept
    }

    /// "Sweep all now" (the shelf button): every currently-fading note straight
    /// to Recently Deleted, ahead of its timer.
    @discardableResult
    static func sweepAllFading(repository: NotesRepository, now: Date = Date()) -> Int {
        let fading = MemoLifecycle.partition(repository.allMemos(), now: now).fading
        for memo in fading { repository.softDelete(memo, at: now) }
        if !fading.isEmpty { DevLog.log("FadingSweep: sweep-all → \(fading.count) note(s)") }
        return fading.count
    }
}
