import Foundation

/// WHICH notes are waiting for a polish pass — one rule for every polisher
/// (the Mac's batch, the iPad's on-demand `PolishCenter`), so a count shown on
/// one device can never mean something else on another.
///
/// The rule is the locked doctrine in code form: **the rating IS the flag.**
/// significance 0 = a note every polisher deliberately skips, so it is NOT
/// waiting for anything — it is waiting for YOU. That distinction is why the
/// iPad's header button and its "N not rated" line count different piles.
enum ProcessPile {
    /// Notes a polisher would pick up right now: rated, live, unlocked, with a
    /// real transcript, and nothing written back yet.
    ///
    /// `enhancedIDs` is the set of memo IDs that already carry polished content
    /// (`MemoEnhancement.hasContent`) — passed in rather than fetched per memo,
    /// because a per-memo fetch inside a SwiftUI body is the frozen-library
    /// trap this project has already paid for once.
    static func waiting(memos: [Memo], enhancedIDs: Set<UUID>) -> [Memo] {
        memos.filter { isWaiting($0, enhancedIDs: enhancedIDs) }
    }

    static func isWaiting(_ memo: Memo, enhancedIDs: Set<UUID>) -> Bool {
        guard memo.significance > 0, memo.deletedAt == nil, !memo.locked else { return false }
        guard !enhancedIDs.contains(memo.id) else { return false }
        return !(memo.transcript ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// Notes carrying no rating — the pile waiting on a human, not a model.
    static func unrated(memos: [Memo]) -> [Memo] {
        memos.filter { $0.significance == 0 && $0.deletedAt == nil && !$0.locked }
    }
}
