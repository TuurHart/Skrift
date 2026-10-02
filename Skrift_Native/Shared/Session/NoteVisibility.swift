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

    // MARK: - Q101: the pure rules every non-list surface applies

    /// What a locked note's row/peek shows in place of its title when it has no explicit one.
    static let placeholderTitle = "Locked note"

    /// Title for a surface that may show a locked note: the note's own title when its
    /// content is visible; when hidden, ONLY an explicitly set title (never the first-line
    /// fallback, which is the note's words), else the placeholder.
    static func displayTitle(locked: Bool, unlockedThisSession: Bool,
                             title: String?, fallback: () -> String) -> String {
        if contentVisible(locked: locked, unlockedThisSession: unlockedThisSession) { return fallback() }
        let t = title?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return t.isEmpty ? placeholderTitle : t
    }

    /// A transcript snippet for a row/pane: nil while the note's content is hidden.
    static func snippet(locked: Bool, unlockedThisSession: Bool, _ text: @autoclosure () -> String?) -> String? {
        contentVisible(locked: locked, unlockedThisSession: unlockedThisSession) ? text() : nil
    }

    /// Free-text search over a note (C91/C161): while the content is hidden the body fields
    /// are out of the match and only the explicitly set title can hit; once unlocked this
    /// session every field counts. Empty query matches all. `bodyFields` is lazy so a hidden
    /// note's words are never even read.
    static func matches(query: String, locked: Bool, unlockedThisSession: Bool,
                        title: String?, bodyFields: () -> [String?]) -> Bool {
        let q = query.trimmingCharacters(in: .whitespaces).lowercased()
        guard !q.isEmpty else { return true }
        if title?.lowercased().contains(q) == true { return true }
        guard contentVisible(locked: locked, unlockedThisSession: unlockedThisSession) else { return false }
        return bodyFields().contains { $0?.lowercased().contains(q) == true }
    }
}
