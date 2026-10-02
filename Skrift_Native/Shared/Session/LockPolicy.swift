import Foundation

/// The lock verbs' POLICY, shared phone↔Mac (Q100): what the phone's
/// `MemosListView.toggleLock` / `deleteMemo` used to carry privately. Foundation-only
/// and closure-injected so the host-less Mac test bundle can exercise it without
/// LocalAuthentication; `LockGate` supplies the real session/auth closures
/// (`LockGate.policy`). Each app keeps only what is platform-specific: saving, the
/// "Already in your vault" alert, the actual soft-delete. Hidden-not-encrypted (C213):
/// auth gates the UI only.
@MainActor
struct LockPolicy {
    var isUnlocked: (String) -> Bool
    var unlock: (String) async -> Bool
    var canAuthenticate: () -> Bool
    var authorizeRemoveLock: () async -> Bool

    /// Delete of a note that may be locked (R88/C161): a locked, not-yet-unlocked note
    /// needs device-owner auth first — the same idiom as removing the lock. Keyed by
    /// the memo UUID string (`PipelineFile.id` is the same string).
    func authorizeDelete(id: String, locked: Bool) async -> Bool {
        if NoteVisibility.contentVisible(locked: locked, unlockedThisSession: isUnlocked(id)) { return true }
        return await unlock(id)
    }

    /// Lock a note: refused when this device can't authenticate (no passcode set —
    /// locking would brick the note here). Instant, no auth. Stamps `markEdited`
    /// (lock isn't title/body/tags, C98, so `stampWords: false`). The CALLER saves.
    /// Returns whether the lock was applied.
    func lock(_ memo: Memo) -> Bool {
        guard canAuthenticate() else { return false }
        memo.locked = true
        memo.markEdited(stampWords: false)
        return true
    }

    /// Remove the lock: requires device-owner auth (Apple Notes idiom). The CALLER saves.
    /// Returns whether the lock was removed.
    func removeLock(_ memo: Memo) async -> Bool {
        guard await authorizeRemoveLock() else { return false }
        memo.locked = false
        memo.markEdited(stampWords: false)
        return true
    }
}
