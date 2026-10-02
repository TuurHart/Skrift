import Foundation
import SwiftData

/// A fetch of the shared `Memo` store through a FRESH `ModelContext`, with that context kept
/// alive beside the memos (Q241 bug 5).
///
/// A CloudKit import writes to the persistent store but does not refresh objects already
/// registered with `mainContext`, so the sidebar fetches through a brand-new context. The memos
/// belong to THAT context: mutating them and saving `mainContext` (which has no change) writes
/// nothing, and a context nobody holds is freed right after the fetch. Mutate the memos, then
/// `save()` the snapshot.
@MainActor
struct CloudMemoSnapshot {
    let context: ModelContext
    let memos: [Memo]

    init(container: ModelContainer) {
        let ctx = ModelContext(container)
        self.context = ctx
        // Q105: ONE row per note id — a CloudKit re-sync can leave exact clones (same UUID) that
        // the phone heals later; until then the list must not draw the note twice. The same
        // keeper rule the reconciler and Journal call (`MemoDuplicates.canonicalRows`).
        self.memos = MemoDuplicates.canonicalRows((try? ctx.fetch(FetchDescriptor<Memo>())) ?? [])
    }

    func save() { try? context.save() }
}
