import Foundation

/// The Fading lifecycle's at-open half (design 2026-07-17, `MemoLifecycle`; v3
/// "no note dies unseen" 2026-07-23): move sweep-due notes (untouched, 60+
/// days) into Recently Deleted — the EXISTING soft-delete, so everything stays
/// visible, restorable, and only the trash's own 14-day countdown ever deletes
/// for real — and stamp the purge clock (`trashSeenAt`) for any trashed note
/// that arrived while this phone sat closed (another device's sweep or delete,
/// synced in). Fully automatic (Tuur, 2026-07-18 device round — the "Start the
/// timers" arming gate read as friction, and the trash's 14 reversible days +
/// the shelf counts are the safety): doing nothing IS the cleanup, from day one.
///
/// Runs ONLY at a human open (launch task + foreground activation — both
/// require the UI scene, which background wakes never attach), per device,
/// idempotent (a note another device already swept is simply no longer live
/// here). That gate is the v3 doctrine: time away never moves the final doors,
/// so a note forgotten for three months is still here at the next open — in
/// Recently Deleted at worst, with its full window to be brought back.
@MainActor
enum FadingSweep {

    /// Stamp sightings, then sweep everything due. Returns the count moved.
    @discardableResult
    static func run(repository: NotesRepository, now: Date = Date()) -> Int {
        // The open-stamp first: an unseen trashed note's purge clock starts at
        // THIS open (repository.softDelete stamps its own below).
        let stamped = MemoLifecycle.stampTrashSightings(repository.deletedMemos(), now: now)
        if stamped > 0 {
            repository.save()
            DevLog.log("FadingSweep: purge clock started for \(stamped) synced-in trashed note(s)")
        }

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
}
