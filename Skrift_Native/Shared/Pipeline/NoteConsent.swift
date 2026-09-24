import Foundation

/// THE rated/unrated predicate — the unrated model (locked 2026-07-26) in one
/// place: **the rating is CONSENT — until judged, Skrift spends nothing on a
/// note and shows it nowhere but back to you.**
///
/// Being unrated changes exactly FIVE things — the note fades
/// (`MemoLifecycle.neverFades`), renders quiet (the sidebar/list rows), never
/// processes (`ProcessPile`, `WayOutRules.needsProcessing`), never exports
/// (`PublishCoordinator`; the Mac pipeline never compiles it), and joins no
/// connections in either direction (index membership AND the panel surface).
/// Everything that is just reading your own note back — play, photos, karaoke,
/// copy, search, edit — is deliberately a normal note.
///
/// Why this type exists (2026-07-28): "is this note rated?" was asked in five
/// hand-rolled copies across two channels — `Memo.significance` (non-optional,
/// 0 = unrated) and `PipelineFile.significance` (optional, nil AND 0 both
/// unrated, nil meaning three different things — see the desktop adapter,
/// `NoteConsent+PipelineFile.swift`) — and every new feature re-tripped one of
/// them ("Process N" counted unrated Mac takes; Connections indexed them).
/// Every rated/unrated ask routes through here now. Per-feature rules still
/// combine this answer with their own locked/deleted/fading logic — those are
/// separate verbs with their own doctrine (lock = keep-don't-polish, trash =
/// lifecycle), not part of the consent model.
///
/// The doors OUT of unrated stay event-shaped at their own sites: the circles
/// (both apps), Polish (`PolishCenter.polishNow` floors to 0.1 — pressing it
/// IS a judgment), and a Mac IMPORT (`MacMemoAuthor`'s 0.1 floor; a Mac
/// RECORDING stays unrated — capturing a thought is not judging it).
enum NoteConsent {

    /// Has this note been judged? `nil` and `0` both mean no —
    /// `ThreeBallScale.step(for:)` is the one dialect-tolerant reading of a
    /// significance value (float-noise and non-finite tolerant too).
    static func isRated(_ significance: Double?) -> Bool {
        ThreeBallScale.step(for: significance) > 0
    }

    /// The memo channel (both apps): non-optional storage, 0 = unrated.
    static func isRated(_ memo: Memo) -> Bool {
        isRated(memo.significance)
    }
}
