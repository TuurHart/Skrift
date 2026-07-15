import Foundation

/// Mac model-typed convenience over the shared `LockGate` (Shared/Session).
/// `PipelineFile.id` is already the memo UUID string — the unified gate key.
extension LockGate {
    /// Whether this row's CONTENT is currently gated.
    func isLocked(_ pf: PipelineFile) -> Bool {
        pf.locked && !isUnlocked(pf.id)
    }
}
