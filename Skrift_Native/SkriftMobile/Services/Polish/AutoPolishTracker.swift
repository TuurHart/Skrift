import Foundation

/// Remembers which memos this session already auto-polished, so "Polish when I open a
/// note" fires at most ONCE per memo per launch. A failed attempt is recorded too — the
/// tracker never lets a note that failed to polish loop on every reopen. Pure +
/// host-testable (iPad wave 1); `PolishCenter.maybeAutoPolish` owns the toggle/canPolish
/// guards around it.
struct AutoPolishTracker {
    private var attempted: Set<UUID> = []

    /// Records `id` and returns true only the FIRST time it is seen this session.
    mutating func firstAttempt(_ id: UUID) -> Bool {
        attempted.insert(id).inserted
    }
}
