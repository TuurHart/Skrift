import Foundation
import SwiftData

/// The note lifecycle — ONE rulebook for both apps. Design v2 **"one clock"**
/// (mocks/lifecycle-triage-peek.html #m5/#m6, signed 2026-07-22; supersedes the
/// 2026-07-17 "anything you touched stays until you say otherwise"):
///
///   **every unrated note is on one fade clock; touching it restarts the clock,
///   rating it keeps it forever. Only locks, reminders and backlinks hold a
///   note off the clock.**
///
/// The clock runs from `clockStart` = max(recordedAt, keptAt): any investment
/// (edit / title / tag / annotate / keep / bring back) writes `keptAt = now`
/// — 30 fresh days, not immortality. A clock-run note leaves
/// the main surfaces at `fadeAfterDays` (Fading), auto-moves to Recently
/// Deleted at `trashAfterDays` (the sweep sets `deletedAt` — the existing
/// soft-delete: visible, restorable, purged after `TrashPolicy.retentionDays`).
/// Everything stays DERIVED; `keptAt` remains the only stored lifecycle bit.
///
/// **v3 amendment — "no note dies unseen" (Tuur, 2026-07-23):** the fade clock
/// keeps running while the apps sit closed (fading is honest about time), but
/// the FINAL doors only move while the user is looking. Sweeps run at app-open
/// (phone launch/foreground; Mac launch/activation — never an unattended
/// timer), and the purge countdown runs from `trashSeenAt` — the first open
/// with the note in the trash — not from `deletedAt`. So a note forgotten for
/// three months is still there at the next open: at worst it lands in Recently
/// Deleted right then, with the full retention window to bring it back.
enum MemoLifecycle {

    static let fadeAfterDays = 30
    static let trashAfterDays = 60

    /// The one clock: recording started it; the freshest touch restarted it.
    static func clockStart(of memo: Memo) -> Date {
        max(memo.ageDate, memo.keptAt ?? .distantPast)
    }

    /// Held OFF the clock entirely: rated (the active track), locked, pending
    /// reminder, or backlinked from a living note. Everything else fades.
    static func neverFades(_ memo: Memo, backlinked: Set<UUID>) -> Bool {
        if NoteConsent.isRated(memo) { return true }
        if memo.locked { return true }
        if memo.remindAt != nil { return true }
        if backlinked.contains(memo.id) { return true }
        return false
    }

    /// On the Fading conveyor: a clock-run note past `fadeAfterDays`, done
    /// processing, not trashed. (Also true past `trashAfterDays` until the sweep
    /// runs — the surface keeps showing a note the sweep hasn't reached yet.)
    static func isFading(_ memo: Memo, backlinked: Set<UUID>, now: Date = Date()) -> Bool {
        guard memo.deletedAt == nil, memo.transcriptStatus == .done else { return false }
        guard !neverFades(memo, backlinked: backlinked) else { return false }
        return age(of: memo, at: now) >= days(fadeAfterDays)
    }

    /// Due for the auto-move to Recently Deleted (the sweep's predicate).
    static func sweepDue(_ memo: Memo, backlinked: Set<UUID>, now: Date = Date()) -> Bool {
        isFading(memo, backlinked: backlinked, now: now) && age(of: memo, at: now) >= days(trashAfterDays)
    }

    /// When this note will auto-move to Recently Deleted (the countdown label).
    static func trashesAt(_ memo: Memo) -> Date {
        clockStart(of: memo).addingTimeInterval(days(trashAfterDays))
    }

    /// When this note crossed (or will cross) onto the Fading conveyor — drives
    /// the phone's unread-style ⋯ dot: lit only for entries NEWER than the last
    /// visit, dark otherwise (an always-on light is no signal).
    static func fadeEntersAt(_ memo: Memo) -> Date {
        clockStart(of: memo).addingTimeInterval(days(fadeAfterDays))
    }

    /// Every memo id referenced by a `[[memo:UUID|…]]` link in another note's
    /// body — backlinked notes never fade. One scan per corpus refresh; pass the
    /// result into the predicates (never scan per row). `copyedits` (memoID →
    /// `MemoEnhancement.copyedit`) adds the polished copy: a Mac-made link syncs in
    /// there, not into the transcript (Q120 — `Backlinks` is the one scan).
    static func backlinkedIDs(in memos: [Memo], copyedits: [UUID: String] = [:]) -> Set<UUID> {
        Backlinks.linkedIDs(in: memos.lazy.filter { $0.deletedAt == nil }.map {
            Backlinks.Row(id: $0.id, transcript: $0.transcript, copyedit: copyedits[$0.id])
        })
    }

    /// Convenience: the corpus split once — (main surfaces, fading conveyor).
    static func partition(_ memos: [Memo], copyedits: [UUID: String] = [:],
                          now: Date = Date()) -> (live: [Memo], fading: [Memo]) {
        partition(memos, backlinked: backlinkedIDs(in: memos, copyedits: copyedits), now: now)
    }

    /// The same split over a backlink set the caller already scanned (one scan per render,
    /// R92/C278). The ONE place the live/fading rule is applied to a list.
    static func partition(_ memos: [Memo], backlinked: Set<UUID>,
                          now: Date = Date()) -> (live: [Memo], fading: [Memo]) {
        var live: [Memo] = [], fading: [Memo] = []
        for m in memos where m.deletedAt == nil {
            if isFading(m, backlinked: backlinked, now: now) { fading.append(m) } else { live.append(m) }
        }
        return (live, fading)
    }

    /// The at-open fading sweep loop (Q172): every live note that is `sweepDue` goes to
    /// Recently Deleted through `softDelete` (the phone passes its repository verb, which
    /// logs and saves; the Mac passes `WayOut.softDelete` and saves once). Backlinks are
    /// scanned once over `live`. Returns how many moved. The caller stamps trash
    /// sightings first (`stampTrashSightings`) and owns saving.
    @discardableResult
    static func sweepFading(live: [Memo], copyedits: [UUID: String] = [:], now: Date = Date(),
                            softDelete: (Memo) -> Void) -> Int {
        let live = live.filter { $0.deletedAt == nil }
        let backlinked = backlinkedIDs(in: live, copyedits: copyedits)
        var swept = 0
        for memo in live where sweepDue(memo, backlinked: backlinked, now: now) {
            softDelete(memo)
            swept += 1
        }
        return swept
    }

    // MARK: - v3 "no note dies unseen" (2026-07-23): the trash clock

    /// The validity rule, one place: a sighting counts only for the CURRENT
    /// stay in the trash (`seenAt >= deletedAt`) — restore → re-trash makes an
    /// old stamp stale by construction, no cleanup pass needed. nil = the note
    /// is not trashed, or nobody has had the app open since it was.
    static func trashClockStart(deletedAt: Date?, seenAt: Date?) -> Date? {
        guard let deletedAt, let seenAt, seenAt >= deletedAt else { return nil }
        return seenAt
    }

    /// When this note's purge clock actually started (valid sighting), or nil
    /// while it hasn't — an unseen trashed note has no clock at all.
    static func trashClockStart(_ memo: Memo) -> Date? {
        trashClockStart(deletedAt: memo.deletedAt, seenAt: memo.trashSeenAt)
    }

    /// Due for the permanent purge: seen in the trash at least
    /// `TrashPolicy.retention` ago (inclusive). Never true for an unseen note —
    /// time away from the app doesn't burn trash days.
    static func purgeDue(_ memo: Memo, now: Date = Date()) -> Bool {
        guard let start = trashClockStart(memo) else { return false }
        return now.timeIntervalSince(start) >= TrashPolicy.retention
    }

    /// When a trashed note is gone for good (the countdown label). An unseen
    /// note reads as a full window from `now` — the truth under the gate: its
    /// clock starts the moment you're looking at it.
    static func goneAt(_ memo: Memo, now: Date = Date()) -> Date {
        (trashClockStart(memo) ?? now).addingTimeInterval(TrashPolicy.retention)
    }

    /// The at-open stamp: start the clock for every trashed note that has no
    /// valid sighting (deletions that synced in, or that pre-date v3). Both
    /// apps call this ONLY on a human open (phone launch/foreground; Mac
    /// launch/activation); the delete gestures stamp their own. Caller saves.
    @discardableResult
    static func stampTrashSightings(_ memos: [Memo], now: Date = Date()) -> Int {
        var stamped = 0
        for m in memos where m.deletedAt != nil && trashClockStart(m) == nil {
            m.trashSeenAt = now
            stamped += 1
        }
        return stamped
    }

    private static func age(of memo: Memo, at now: Date) -> TimeInterval {
        now.timeIntervalSince(clockStart(of: memo))
    }
    /// `n` whole days as a time interval — the one day-length both clocks use (`MemoSpine` too).
    static func days(_ n: Int) -> TimeInterval { TimeInterval(n) * 86_400 }
}
