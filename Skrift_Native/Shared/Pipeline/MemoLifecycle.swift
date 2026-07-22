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
/// via `touch(_:)` — 30 fresh days, not immortality. A clock-run note leaves
/// the main surfaces at `fadeAfterDays` (Fading), auto-moves to Recently
/// Deleted at `trashAfterDays` (the sweep sets `deletedAt` — the existing
/// soft-delete: visible, restorable, purged after `TrashPolicy.retentionDays`).
/// Everything stays DERIVED; `keptAt` remains the only stored lifecycle bit.
enum MemoLifecycle {

    static let fadeAfterDays = 30
    static let trashAfterDays = 60

    /// The one clock: recording started it; the freshest touch restarted it.
    static func clockStart(of memo: Memo) -> Date {
        max(memo.recordedAt, memo.keptAt ?? .distantPast)
    }

    /// The bump — call at every investment site (transcript-edit / title / tag /
    /// annotation commits, Keep, Bring back). 30 fresh days from `now`.
    static func touch(_ memo: Memo, now: Date = Date()) {
        memo.keptAt = now
    }

    /// Held OFF the clock entirely: rated (the active track), locked, pending
    /// reminder, or backlinked from a living note. Everything else fades.
    static func neverFades(_ memo: Memo, backlinked: Set<UUID>) -> Bool {
        if memo.significance > 0 { return true }
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
    static func fadesAt(_ memo: Memo) -> Date {
        clockStart(of: memo).addingTimeInterval(days(trashAfterDays))
    }

    /// When this note crossed (or will cross) onto the Fading conveyor — drives
    /// the phone's unread-style ⋯ dot: lit only for entries NEWER than the last
    /// visit, dark otherwise (an always-on light is no signal).
    static func fadeEntersAt(_ memo: Memo) -> Date {
        clockStart(of: memo).addingTimeInterval(days(fadeAfterDays))
    }

    /// Whole days until the auto-move (0 = "fades today"; never negative).
    static func daysUntilSweep(_ memo: Memo, now: Date = Date()) -> Int {
        max(0, Int(ceil(fadesAt(memo).timeIntervalSince(now) / 86_400)))
    }

    /// Every memo id referenced by a `[[memo:UUID|…]]` link in another note's
    /// body — backlinked notes never fade. One scan per corpus refresh; pass the
    /// result into the predicates (never scan per row).
    static func backlinkedIDs(in memos: [Memo]) -> Set<UUID> {
        var out: Set<UUID> = []
        for memo in memos where memo.deletedAt == nil {
            guard let body = memo.transcript, body.contains("[[memo:") else { continue }
            for occ in MemoLinkSyntax.occurrences(in: body) { out.insert(occ.id) }
        }
        return out
    }

    /// Convenience: the corpus split once — (main surfaces, fading conveyor).
    static func partition(_ memos: [Memo], now: Date = Date()) -> (live: [Memo], fading: [Memo]) {
        let backlinked = backlinkedIDs(in: memos)
        var live: [Memo] = [], fading: [Memo] = []
        for m in memos where m.deletedAt == nil {
            if isFading(m, backlinked: backlinked, now: now) { fading.append(m) } else { live.append(m) }
        }
        return (live, fading)
    }

    // MARK: - one-clock migration (2026-07-22, run once per device)

    /// Old-doctrine parked notes — touched-but-unrated, where edit/title/tag/
    /// annotation used to BE immortality and never wrote `keptAt` — get a fresh
    /// clock once, so the doctrine switch can't fade anything out from under the
    /// user. Idempotent per note (`keptAt == nil` guard); the caller gates the
    /// pass with a defaults flag and saves the context.
    @discardableResult
    static func migrateParkedToOneClock(_ memos: [Memo], now: Date = Date()) -> Int {
        var bumped = 0
        for m in memos where m.deletedAt == nil && m.significance == 0 && m.keptAt == nil {
            let wasParked = m.transcriptUserEdited
                || !(m.title ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                || !m.tags.isEmpty
                || !(m.annotationText ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            if wasParked {
                m.keptAt = now
                bumped += 1
            }
        }
        return bumped
    }

    /// Once-per-device runner for the migration above — both apps call it at
    /// launch against their cloud store. The flag is per-device on purpose:
    /// `keptAt = now` twice (two devices racing) converges to near-identical
    /// values, so re-running elsewhere is harmless.
    static func runOneClockMigrationOnce(context: ModelContext,
                                         defaults: UserDefaults = .standard,
                                         now: Date = Date()) {
        let key = "oneClockMigrated.v1"
        guard !defaults.bool(forKey: key) else { return }
        guard let memos = try? context.fetch(FetchDescriptor<Memo>()) else { return }
        if migrateParkedToOneClock(memos, now: now) > 0 {
            try? context.save()
        }
        defaults.set(true, forKey: key)
    }

    private static func age(of memo: Memo, at now: Date) -> TimeInterval {
        now.timeIntervalSince(clockStart(of: memo))
    }
    private static func days(_ n: Int) -> TimeInterval { TimeInterval(n) * 86_400 }
}
