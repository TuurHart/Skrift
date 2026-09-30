import Foundation

/// The way-out shelf (Fading + Recently Deleted) — the rules both apps share (Q82 group 9).
/// The phone's `WayOutView` and the Mac's `WayOutRules`/`WayOutColumn` each carried a copy of
/// bring-back, the imminence order, the one-liner and the countdown threshold; they read the
/// same `MemoLifecycle` clock, so they now read the same helpers too.
enum WayOut {

    /// A countdown turns urgent (red) inside this many days.
    static let urgentDays = 3

    /// The one rescue verb for a fading and a deleted note: `keptAt` ALWAYS (an explicit
    /// rescue is a touch, so the note must not re-fade the next second), `deletedAt` cleared.
    /// The caller saves.
    static func bringBack(_ memo: Memo, now: Date = Date()) {
        memo.keptAt = now
        memo.deletedAt = nil
        memo.trashSeenAt = nil   // purge-clock hygiene (v3); the validity guard ignores stale stamps anyway
    }

    /// Fading rows, soonest-to-move-to-Recently-Deleted first.
    static func fadingOrdered(_ memos: [Memo]) -> [Memo] {
        memos.sorted { MemoLifecycle.fadesAt($0) < MemoLifecycle.fadesAt($1) }
    }

    /// Deleted rows, soonest-to-be-purged-for-good first (a row without a date sorts last).
    static func deletedOrdered(_ memos: [Memo]) -> [Memo] {
        memos.sorted { ($0.deletedAt ?? .distantFuture) < ($1.deletedAt ?? .distantFuture) }
    }

    /// The spine's one-liner for a note — "moves to Recently Deleted in Nd" while fading,
    /// "gone for good in ~Nd" once deleted.
    static func oneLiner(for memo: Memo, backlinked: Set<UUID> = [], now: Date = Date()) -> String {
        MemoSpine.oneLiner(for: MemoSpine.station(for: .from(memo, backlinked: backlinked), now: now), now: now)
    }

    /// Whole days until `date` (0 = today; never negative).
    static func daysLeft(until date: Date, now: Date = Date()) -> Int {
        max(0, Int(ceil(date.timeIntervalSince(now) / 86_400)))
    }

    /// Red inside the countdown's last `urgentDays`, for both the fading and the deleted row.
    static func isUrgent(_ station: MemoSpine.Station, now: Date = Date()) -> Bool {
        switch station {
        case .fading(let deletedAt): return daysLeft(until: deletedAt, now: now) <= urgentDays
        case .deleted(let goneAt):   return daysLeft(until: goneAt, now: now) <= urgentDays
        default:                     return false
        }
    }
}
