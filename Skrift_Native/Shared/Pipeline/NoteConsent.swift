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
/// IS a judgment; NOT on the Mac, whose Process just skips unrated notes). A Mac
/// import and a Mac recording both arrive unrated (D159) — neither is a judgment.
enum NoteConsent {

    /// Has this note been judged? `nil` and `0` both mean no —
    /// `ThreeBallScale.step(for:)` is the one dialect-tolerant reading of a
    /// significance value (float-noise and non-finite tolerant too).
    static func isRated(_ significance: Double?) -> Bool {
        ThreeBallScale.step(for: significance) > 0
    }

    /// What pressing Process / Polish on an unrated note writes (C40/D159): a judgment, the
    /// 0.1 floor of the three-ball scale. `PolishCenter.polishNow` writes the same literal.
    static let processFloor = 0.1

    /// The significance a note carries after Process is pressed on it: an unrated note is
    /// floored to `processFloor`; a rated one keeps its own (pressing Process never lowers it).
    static func flooredByProcess(_ significance: Double?) -> Double {
        isRated(significance) ? (significance ?? processFloor) : processFloor
    }

    /// The memo channel (both apps): non-optional storage, 0 = unrated.
    static func isRated(_ memo: Memo) -> Bool {
        isRated(memo.significance)
    }
}
