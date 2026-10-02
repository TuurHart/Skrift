import Foundation

/// Phone model-typed conveniences over the shared `LockGate` (Shared/Session).
/// The gate keys on the memo UUID **string** (the unified key); these bridge the
/// phone's `Memo`/`UUID` call sites onto it.
extension LockGate {
    /// Whether this memo's CONTENT is currently gated — routes through the
    /// ONE Shared predicate (`NoteVisibility`, R88) so every surface (list
    /// rows, WayOutView, copy) agrees with the detail page's gate.
    func isLocked(_ memo: Memo) -> Bool {
        !NoteVisibility.contentVisible(locked: memo.locked, unlockedThisSession: isUnlocked(memo.id.uuidString))
    }

    /// Face ID → unlock for this session. Returns whether the content may show.
    func unlock(_ id: UUID) async -> Bool {
        await unlock(id.uuidString)
    }
}
