import Foundation
import SwiftData

/// R94/C281 — nine of the ~ten main-actor sweeps `SkriftApp` fires on every launch
/// and every foreground fully re-derive from the corpus even when nothing changed.
/// This tracks a high-water mark (last-seen memo count + latest edit timestamp) and
/// tells the caller whether the corpus moved since the last check, so the sweep
/// BODIES can no-op when it hasn't.
///
/// NOT consulted by the recording-recovery sweep (C99) — that one stays first and
/// unconditional on every call, gate or no gate.
@MainActor
enum LaunchWorkGate {
    private static var lastCount: Int?
    private static var lastLatestEdit: Date?

    /// True on the very first call (nothing seen yet) or when the memo count or the
    /// latest `editedAt` changed since the last call; false when the corpus is
    /// identical to what was last seen. Advances the mark as a side effect — call
    /// this ONCE per launch/foreground pass, before running the gated sweeps, not
    /// once per sweep.
    static func shouldRunSweeps(repository: NotesRepository) -> Bool {
        let count = (try? repository.context.fetchCount(FetchDescriptor<Memo>())) ?? 0

        var latestDescriptor = FetchDescriptor<Memo>(
            predicate: #Predicate<Memo> { $0.editedAt != nil },
            sortBy: [SortDescriptor(\Memo.editedAt, order: .reverse)]
        )
        latestDescriptor.fetchLimit = 1
        latestDescriptor.propertiesToFetch = [\.editedAt]
        let latest = (try? repository.context.fetch(latestDescriptor))?.first?.editedAt

        let changed = lastCount == nil || count != lastCount || latest != lastLatestEdit
        lastCount = count
        lastLatestEdit = latest
        return changed
    }

    #if DEBUG
    /// Test-only: start each case from a clean mark (the mark is process-lifetime
    /// state, same as a real app's launch → foreground sequence).
    static func resetForTesting() {
        lastCount = nil
        lastLatestEdit = nil
    }
    #endif
}
