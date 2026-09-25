import Foundation

/// Mac model-typed convenience over the shared `LockGate` (Shared/Session).
/// `PipelineFile.id` is already the memo UUID string — the unified gate key.
extension LockGate {
    /// Whether this row's CONTENT is currently gated — routes through the ONE
    /// Shared predicate (`NoteVisibility`, R88/C161/C213/C91), matching the phone's
    /// `LockGate+Memo.isLocked` exactly (sweep E finding #1).
    func isLocked(_ pf: PipelineFile) -> Bool {
        !NoteVisibility.contentVisible(locked: pf.locked, unlockedThisSession: isUnlocked(pf.id))
    }
}
