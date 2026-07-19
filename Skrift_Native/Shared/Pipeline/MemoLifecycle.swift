import Foundation

/// The note lifecycle — ONE rulebook for both apps (design locked 2026-07-17,
/// mock `mocks/fading-shelf.html`):
///
///   **a note you never invested in fades out by itself; anything you touched
///   stays until you say otherwise.**
///
/// Untouched notes leave the main surfaces after `fadeAfterDays` (the Fading
/// shelf), auto-move to Recently Deleted at `trashAfterDays` (the sweep sets
/// `deletedAt` — the existing soft-delete: visible, restorable, purged after
/// `TrashPolicy.retentionDays`). Fading is DERIVED — no stored state, no
/// migration, retroactive; the only stored bit is `Memo.keptAt` (rescue).
/// Deletion is never automatic beyond that existing trash countdown.
enum MemoLifecycle {

    static let fadeAfterDays = 30
    static let trashAfterDays = 60

    /// Any explicit investment — a touched note NEVER fades. Photos and bare
    /// share-captures are deliberately NOT touches (Tuur, 2026-07-17).
    static func isTouched(_ memo: Memo, backlinked: Set<UUID>) -> Bool {
        if memo.significance > 0 { return true }
        if memo.transcriptUserEdited { return true }
        if !(memo.title ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return true }
        if !memo.tags.isEmpty { return true }
        if memo.locked { return true }
        if memo.remindAt != nil { return true }
        if !(memo.annotationText ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return true }
        if memo.keptAt != nil { return true }
        if backlinked.contains(memo.id) { return true }
        return false
    }

    /// On the Fading shelf: untouched, done processing, not trashed, and past
    /// `fadeAfterDays`. (Also true past `trashAfterDays` until the sweep runs —
    /// the shelf keeps showing a note the sweep hasn't reached yet.)
    static func isFading(_ memo: Memo, backlinked: Set<UUID>, now: Date = Date()) -> Bool {
        guard memo.deletedAt == nil, memo.transcriptStatus == .done else { return false }
        guard !isTouched(memo, backlinked: backlinked) else { return false }
        return age(of: memo, at: now) >= days(fadeAfterDays)
    }

    /// Due for the auto-move to Recently Deleted (the sweep's predicate).
    static func sweepDue(_ memo: Memo, backlinked: Set<UUID>, now: Date = Date()) -> Bool {
        isFading(memo, backlinked: backlinked, now: now) && age(of: memo, at: now) >= days(trashAfterDays)
    }

    /// When this note will auto-move to Recently Deleted (the countdown label).
    static func fadesAt(_ memo: Memo) -> Date {
        memo.recordedAt.addingTimeInterval(days(trashAfterDays))
    }

    /// When this note crossed (or will cross) onto the Fading shelf — drives the
    /// phone's unread-style ⋯ dot: lit only for entries NEWER than the last
    /// shelf visit, dark otherwise (an always-on light is no signal).
    static func fadeEntersAt(_ memo: Memo) -> Date {
        memo.recordedAt.addingTimeInterval(days(fadeAfterDays))
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

    /// Convenience: the corpus split once — (main surfaces, fading shelf).
    static func partition(_ memos: [Memo], now: Date = Date()) -> (live: [Memo], fading: [Memo]) {
        let backlinked = backlinkedIDs(in: memos)
        var live: [Memo] = [], fading: [Memo] = []
        for m in memos where m.deletedAt == nil {
            if isFading(m, backlinked: backlinked, now: now) { fading.append(m) } else { live.append(m) }
        }
        return (live, fading)
    }

    private static func age(of memo: Memo, at now: Date) -> TimeInterval {
        now.timeIntervalSince(memo.recordedAt)
    }
    private static func days(_ n: Int) -> TimeInterval { TimeInterval(n) * 86_400 }
}
