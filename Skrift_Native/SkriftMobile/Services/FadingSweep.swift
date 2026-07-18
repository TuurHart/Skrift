import Foundation

/// The Fading lifecycle's timed half (design 2026-07-17, `MemoLifecycle`): move
/// sweep-due notes (untouched, 60+ days) into Recently Deleted — the EXISTING
/// soft-delete, so everything stays visible, restorable, and only the trash's
/// own 14-day countdown ever deletes for real.
///
/// Runs on launch, per device, idempotent (a note another device already swept
/// is simply no longer live here). ARMED-gated: the first-run shelf prompt is
/// the one explicit consent — until "Start the timers" is tapped on THIS device
/// it never moves anything (the shelf still shows what qualifies).
@MainActor
enum FadingSweep {
    static let armedKey = "fadingTimersArmed"

    static var armed: Bool { UserDefaults.standard.bool(forKey: armedKey) }
    static func arm() { UserDefaults.standard.set(true, forKey: armedKey) }

    /// Sweep everything due. Returns the count moved (0 when unarmed).
    @discardableResult
    static func run(repository: NotesRepository, now: Date = Date()) -> Int {
        guard armed else { return 0 }
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
    /// to Recently Deleted, ahead of its timer. Also arms.
    @discardableResult
    static func sweepAllFading(repository: NotesRepository, now: Date = Date()) -> Int {
        arm()
        let fading = MemoLifecycle.partition(repository.allMemos(), now: now).fading
        for memo in fading { repository.softDelete(memo, at: now) }
        if !fading.isEmpty { DevLog.log("FadingSweep: sweep-all → \(fading.count) note(s)") }
        return fading.count
    }
}
