import Foundation

/// ONE predicate deciding whether a locked note's content (title, transcript,
/// photos — anything beyond "locked ⇒ title + 🔒 only") may show without auth
/// (R88, C161/C213/C91): every surface that can reveal a note's content —
/// list rows, the Fading/Recently Deleted shelf (`WayOutView`), copy — routes
/// through this so a new surface can't reintroduce the leak. Locking is
/// hidden-not-encrypted and per-session (`LockGate` tracks the session side);
/// this predicate is the pure decision the gate and every view apply.
enum NoteVisibility {
    static func contentVisible(locked: Bool, unlockedThisSession: Bool) -> Bool {
        !locked || unlockedThisSession
    }
}
