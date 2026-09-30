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
    /// `enhancedIDs` is the set of memo IDs a polish pass has already RUN for
    /// (`MemoEnhancement.isProcessed`, not `hasContent` — a pass that produced
    /// nothing still counts, or the note never leaves this pile) — passed in
    /// rather than fetched per memo, because a per-memo fetch inside a SwiftUI
    /// body is the frozen-library trap this project has already paid for once.
    static func waiting(memos: [Memo], enhancedIDs: Set<UUID>) -> [Memo] {
        memos.filter { isWaiting($0, enhancedIDs: enhancedIDs) }
    }

    static func isWaiting(_ memo: Memo, enhancedIDs: Set<UUID>) -> Bool {
        guard NoteConsent.isRated(memo), memo.deletedAt == nil, !memo.locked else { return false }
        guard !enhancedIDs.contains(memo.id) else { return false }
        return !(memo.transcript ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// Notes carrying no rating — the pile waiting on a human, not a model.
    static func unrated(memos: [Memo]) -> [Memo] {
        memos.filter { !NoteConsent.isRated($0) && $0.deletedAt == nil && !$0.locked }
    }

    static func isDone(_ memo: Memo, enhancedIDs: Set<UUID>) -> Bool {
        NoteConsent.isRated(memo) && memo.deletedAt == nil && !memo.locked
            && enhancedIDs.contains(memo.id)
    }

    // MARK: - The triage chips (shared QueueFilter, matched against a Memo)

    /// Does a memo belong under `filter`'s chip? The iPad's answer to the Mac's
    /// `AppModel.matchesFilter` — same four words, memo semantics. `.needsWork`
    /// here is the broad "rated but not done yet" set (may include a note still
    /// transcribing); the to-process COUNT is the actionable subset `waiting`,
    /// exactly as the Mac's "Needs Work" chip is broader than its Process count.
    static func matches(_ filter: QueueFilter, _ memo: Memo, enhancedIDs: Set<UUID>) -> Bool {
        switch filter {
        case .all:      return true
        case .needsWork: return NoteConsent.isRated(memo) && !enhancedIDs.contains(memo.id)
        case .done:     return NoteConsent.isRated(memo) && enhancedIDs.contains(memo.id)
        case .notRated: return !NoteConsent.isRated(memo) && !memo.locked
        }
    }
}
