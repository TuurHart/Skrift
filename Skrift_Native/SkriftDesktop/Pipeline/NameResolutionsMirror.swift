import Foundation

/// The note's name DECISIONS (unlink / pick / silence) between the Mac's `PipelineFile` and
/// the synced `Memo` — one shared blob on both sides (`NameResolutions`, C81 / D20 / R37), so
/// a decision made on any device is honoured by the `Sanitiser` on every other.
///
/// Kept apart from `MirroredNoteFields` on purpose: that list's tests pin its exact members,
/// and this field has a third behaviour the plain mirror does not — moving the Mac's
/// pre-2026-10 decisions (`PipelineFile.legacyUnlinkedNames` / `legacyNamePicksJSON`) out
/// once. The callers are the same three seams: `MemoCloudIngest` (first contact),
/// `MemoCloudUpdate` (phone → Mac), `MacCloudMetaSync` (Mac → phone).
enum NameResolutionsMirror {

    /// phone → Mac (first contact and every live update). Returns true when it changed the
    /// row — the caller then re-links + recompiles, because the links reach the body.
    /// An un-migrated Mac decision is never wiped by a memo that has never heard of it:
    /// it goes OUT first (`migrateLegacy`), then the two agree.
    @discardableResult
    static func pull(_ memo: Memo, into pf: PipelineFile) -> Bool {
        let phone = memo.nameResolutions
        if pf.hasLegacyNameResolutions {
            guard !phone.isEmpty else { return false }
            pf.nameResolutions = phone   // the synced decision wins over an unsynced legacy one
            return true
        }
        guard pf.nameResolutions != phone else { return false }
        pf.nameResolutions = phone
        return true
    }

    /// Mac → phone: put the row's decisions on the synced `Memo`. Value-compared, so an
    /// agreeing memo is not churned. Driven by an actual Mac decision (an EVENT —
    /// `MacCloudMetaSync.setNameResolutions`), never by the passive pass, so a stale row can
    /// not clobber a newer phone decision on an unrelated tag edit.
    @discardableResult
    static func push(_ pf: PipelineFile, to memo: Memo) -> Bool {
        let mine = pf.nameResolutions
        guard memo.nameResolutions != mine else { return false }
        memo.nameResolutions = mine
        return true
    }

    /// The one passive Mac → phone move: a row still holding pre-shared-blob decisions, on a
    /// memo with none, folds them into the shared blob and sends them. Safe on the passive
    /// pass because it only ever fills an EMPTY memo.
    @discardableResult
    static func migrateLegacy(_ pf: PipelineFile, to memo: Memo) -> Bool {
        guard pf.hasLegacyNameResolutions, memo.nameResolutions.isEmpty else { return false }
        pf.nameResolutions = pf.nameResolutions   // fold legacy → blob, clear the legacy copies
        return push(pf, to: memo)
    }
}
