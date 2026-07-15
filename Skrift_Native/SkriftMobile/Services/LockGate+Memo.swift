import Foundation

/// Phone model-typed conveniences over the shared `LockGate` (Shared/Session).
/// The gate keys on the memo UUID **string** (the unified key); these bridge the
/// phone's `Memo`/`UUID` call sites onto it.
extension LockGate {
    /// Whether this memo's CONTENT is currently gated.
    func isLocked(_ memo: Memo) -> Bool {
        memo.locked && !isUnlocked(memo.id.uuidString)
    }

    /// Face ID → unlock for this session. Returns whether the content may show.
    func unlock(_ id: UUID) async -> Bool {
        await unlock(id.uuidString)
    }
}
